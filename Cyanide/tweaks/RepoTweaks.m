//
//  RepoTweaks.m
//

#import <JavaScriptCore/JavaScriptCore.h>
#import "RepoTweaks.h"
#import "QuickLoader.h"
#import "remote_objc.h"
#import "../TaskRop/RemoteCall.h"
#import "../LogTextView.h"

extern uint64_t r_nsstr_retained(const char *str);

// =============================================================================
// Global registry, kill switch and dealing with multithreading (NSRecursiveLock)
// =============================================================================
static NSMutableDictionary<NSString *, JSContext *> *g_repo_contexts = nil;
static NSMutableDictionary<NSString *, NSMutableDictionary *> *g_repo_timers_registry = nil;
static int g_repo_timer_id_counter = 0;

static volatile int g_repo_shutting_down = 0;
// Using NSRecursiveLock to avoid deadlock if the same thread makes multiple calls at the same time
static NSRecursiveLock *g_repo_ipc_lock = nil; 

static uint64_t repo_js_to_uint64(JSValue *val) {
    if ([val isString]) return strtoull([[val toString] UTF8String], NULL, 16);
    return (uint64_t)[val toDouble];
}

static NSString* repo_uint64_to_js(uint64_t val) {
    return [NSString stringWithFormat:@"0x%llx", val];
}

// =============================================================================
// js interpreter
// =============================================================================
bool repotweaks_run_isolated_js(NSString *tweakID, NSString *tweakName, NSString *jsCode) {
    if (!jsCode || jsCode.length == 0) return false;
    
    if (!g_repo_ipc_lock) g_repo_ipc_lock = [[NSRecursiveLock alloc] init];
    if (!g_repo_contexts) g_repo_contexts = [[NSMutableDictionary alloc] init];
    if (!g_repo_timers_registry) g_repo_timers_registry = [[NSMutableDictionary alloc] init];
    
    NSMutableDictionary *tweakTimers = g_repo_timers_registry[tweakID];
    if (tweakTimers) {
        for (id timerSource in tweakTimers.allValues) {
            dispatch_source_cancel((dispatch_source_t)timerSource);
        }
        [tweakTimers removeAllObjects];
    } else {
        tweakTimers = [[NSMutableDictionary alloc] init];
        g_repo_timers_registry[tweakID] = tweakTimers;
    }
    
    JSContext *context = [[JSContext alloc] init];
    g_repo_contexts[tweakID] = context;
    
    context.exceptionHandler = ^(JSContext *ctx, JSValue *exception) {
        log_user("[RepoTweaks ERROR][%s] %s\n", [tweakName UTF8String], [[exception toString] UTF8String]);
    };
    
    context[@"setInterval"] = ^JSValue*(JSValue *func, JSValue *delay) {
        int tId = ++g_repo_timer_id_counter;
        uint64_t ms = [delay toUInt32];
        if (ms < 16) ms = 16;
        
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0));
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, ms * NSEC_PER_MSEC), ms * NSEC_PER_MSEC, (ms / 10) * NSEC_PER_MSEC);
        dispatch_source_set_event_handler(timer, ^{
            if (g_repo_shutting_down) return;
            
            [g_repo_ipc_lock lock];
            if (!g_repo_shutting_down) {
                [func callWithArguments:@[]];
            }
            [g_repo_ipc_lock unlock];
        });
        
        tweakTimers[@(tId)] = timer;
        dispatch_resume(timer);
        return [JSValue valueWithInt32:tId inContext:[JSContext currentContext]];
    };

    context[@"clearInterval"] = ^(JSValue *timerId) {
        int tId = [timerId toInt32];
        dispatch_source_t timer = tweakTimers[@(tId)];
        if (timer) {
            dispatch_source_cancel(timer);
            [tweakTimers removeObjectForKey:@(tId)];
        }
    };
    
    context[@"setTimeout"] = ^JSValue*(JSValue *func, JSValue *delay) {
        int tId = ++g_repo_timer_id_counter;
        uint64_t ms = [delay toUInt32];
        
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0));
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, ms * NSEC_PER_MSEC), DISPATCH_TIME_FOREVER, 0);
        dispatch_source_set_event_handler(timer, ^{
            if (g_repo_shutting_down) return;
            
            [g_repo_ipc_lock lock];
            if (!g_repo_shutting_down) {
                [func callWithArguments:@[]];
            }
            [g_repo_ipc_lock unlock];
            
            dispatch_source_cancel(timer);
            [tweakTimers removeObjectForKey:@(tId)];
        });
        
        tweakTimers[@(tId)] = timer;
        dispatch_resume(timer);
        return [JSValue valueWithInt32:tId inContext:[JSContext currentContext]];
    };

    // =============================================================================
    // bridge ipc core - safe for multithreading
    // Avoids different tweaks using the same thread at the same time, waiting system
    // =============================================================================
    context[@"log"] = ^(NSString *msg) {
        if (g_repo_shutting_down) return;
        log_user("[RepoTweaks][%s] %s\n", [tweakName UTF8String], [msg UTF8String]);
    };
    
    context[@"r_sel"] = ^NSString*(NSString *selName) {
        [g_repo_ipc_lock lock];
        if (g_repo_shutting_down) { [g_repo_ipc_lock unlock]; return repo_uint64_to_js(0); }
        uint64_t selPtr = (uint64_t)sel_registerName([selName UTF8String]);
        [g_repo_ipc_lock unlock];
        return repo_uint64_to_js(selPtr);
    };
    
    context[@"r_class"] = ^NSString*(NSString *className) {
        [g_repo_ipc_lock lock];
        if (g_repo_shutting_down) { [g_repo_ipc_lock unlock]; return repo_uint64_to_js(0); }
        uint64_t res = r_class([className UTF8String]);
        [g_repo_ipc_lock unlock];
        return repo_uint64_to_js(res);
    };
    
    context[@"r_msg2"] = ^() {
        [g_repo_ipc_lock lock];
        if (g_repo_shutting_down) { [g_repo_ipc_lock unlock]; return repo_uint64_to_js(0); }
        
        NSArray *args = [JSContext currentArguments];
        if (args.count < 2) { [g_repo_ipc_lock unlock]; return repo_uint64_to_js(0); }
        
        uint64_t target = repo_js_to_uint64(args[0]);
        NSString *selector = [args[1] toString];
        uint64_t a1 = args.count > 2 ? repo_js_to_uint64(args[2]) : 0;
        uint64_t a2 = args.count > 3 ? repo_js_to_uint64(args[3]) : 0;
        uint64_t a3 = args.count > 4 ? repo_js_to_uint64(args[4]) : 0;
        uint64_t a4 = args.count > 5 ? repo_js_to_uint64(args[5]) : 0;
        
        uint64_t res = r_msg2(target, [selector UTF8String], a1, a2, a3, a4);
        [g_repo_ipc_lock unlock];
        return repo_uint64_to_js(res);
    };
    
    context[@"r_msg2_main"] = ^() {
        [g_repo_ipc_lock lock];
        if (g_repo_shutting_down) { [g_repo_ipc_lock unlock]; return repo_uint64_to_js(0); }
        
        NSArray *args = [JSContext currentArguments];
        if (args.count < 2) { [g_repo_ipc_lock unlock]; return repo_uint64_to_js(0); }
        
        uint64_t target = repo_js_to_uint64(args[0]);
        NSString *selector = [args[1] toString];
        uint64_t a1 = args.count > 2 ? repo_js_to_uint64(args[2]) : 0;
        uint64_t a2 = args.count > 3 ? repo_js_to_uint64(args[3]) : 0;
        uint64_t a3 = args.count > 4 ? repo_js_to_uint64(args[4]) : 0;
        uint64_t a4 = args.count > 5 ? repo_js_to_uint64(args[5]) : 0;
        
        uint64_t res = r_msg2_main(target, [selector UTF8String], a1, a2, a3, a4);
        [g_repo_ipc_lock unlock];
        return repo_uint64_to_js(res);
    };

    context[@"r_nsstr"] = ^NSString*(NSString *str) {
        [g_repo_ipc_lock lock];
        if (g_repo_shutting_down || !str) { [g_repo_ipc_lock unlock]; return repo_uint64_to_js(0); }
        uint64_t ptr = r_nsstr_retained([str UTF8String]);
        [g_repo_ipc_lock unlock];
        return repo_uint64_to_js(ptr);
    };

    [g_repo_ipc_lock lock];
    if (!g_repo_shutting_down) {
        [context evaluateScript:jsCode];
    }
    [g_repo_ipc_lock unlock];
    
    return true;
}

// =============================================================================
// runner engine with auto default-values loading
// =============================================================================
bool repotweaks_apply_in_session(void) {
    __sync_lock_test_and_set(&g_repo_shutting_down, 0); 
    
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSDictionary *allRepos = [d dictionaryForKey:@"RepoTweaksCaches"];
    if (!allRepos) return false;
    bool executedAny = false;
    
    for (NSString *url in allRepos) {
        NSDictionary *repoData = allRepos[url];
        NSArray *tweaks = repoData[@"tweaks"];
        for (NSDictionary *tweak in tweaks) {
            NSString *tweakID = tweak[@"id"];
            NSString *toggleKey = [NSString stringWithFormat:@"RepoTweakEnabled_%@", tweakID];
            
            if ([d boolForKey:toggleKey]) {
                NSString *scriptKey = [NSString stringWithFormat:@"RepoTweakScript_%@", tweakID];
                NSString *rawJsCode = [d stringForKey:scriptKey];
                
                if (rawJsCode && rawJsCode.length > 0) {
                    NSMutableString *finalScript = [NSMutableString stringWithString:@"// --- REPOTWEAKS JIT INJECTION ---\n"];
                    NSString *valuesKey = [NSString stringWithFormat:@"RepoTweakValues_%@", tweakID];
                    
                    // Carichiamo il dizionario esistente in modalità modificabile (mutableCopy)
                    NSMutableDictionary *savedValues = [[d dictionaryForKey:valuesKey] mutableCopy] ?: [NSMutableDictionary dictionary];
                    BOOL didUpdateDefaults = NO;
                    
                    NSArray *lines = [rawJsCode componentsSeparatedByString:@"\n"];
                    for (NSString *line in lines) {
                        if ([line containsString:@"@param:"]) {
                            NSArray *parts = [line componentsSeparatedByString:@"|"];
                            if (parts.count >= 4) {
                                NSString *rawType = [parts[0] componentsSeparatedByString:@"@param:"][1];
                                NSString *type = [rawType stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                                NSString *varName = [parts[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                                NSString *defValue = [parts[3] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                                
                                //if new, loads default from .js
                                NSString *currentValue = savedValues[varName];
                                if (!currentValue) {
                                    currentValue = defValue;
                                    savedValues[varName] = defValue; //save locally
                                    didUpdateDefaults = YES;
                                }
                                
                                if ([type isEqualToString:@"switch"]) {
                                    [finalScript appendFormat:@"var %@ = %@;\n", varName, currentValue];
                                } else if ([type isEqualToString:@"text"] || [type isEqualToString:@"color"]) {
                                    [finalScript appendFormat:@"var %@ = \"%@\";\n", varName, currentValue];
                                } else if ([type isEqualToString:@"slider"] || [type isEqualToString:@"number"]) {
                                    [finalScript appendFormat:@"var %@ = %@;\n", varName, currentValue];
                                }
                            }
                        }
                    }
                    
                    if (didUpdateDefaults) {
                        [d setObject:savedValues forKey:valuesKey];
                        [d synchronize];
                    }
                    
                    [finalScript appendString:@"// --------------------------------\n\n"];
                    [finalScript appendString:rawJsCode];
                    
                    log_user("[RepoTweaks] Spawning sandbox for: %s\n", [tweak[@"name"] UTF8String]);
                    repotweaks_run_isolated_js(tweakID, tweak[@"name"], finalScript);
                    executedAny = true;
                }
            } else {
                NSMutableDictionary *tweakTimers = g_repo_timers_registry[tweakID];
                if (tweakTimers && tweakTimers.count > 0) {
                    log_user("[RepoTweaks Garbage Collector] Purging background timers for disabled tweak: %s\n", [tweak[@"name"] UTF8String]);
                    for (id timerSource in tweakTimers.allValues) {
                        dispatch_source_cancel((dispatch_source_t)timerSource);
                    }
                    [tweakTimers removeAllObjects];
                    [g_repo_contexts removeObjectForKey:tweakID];
                }
            }
        }
    }
    return executedAny;
}

void repotweaks_refresh_repo(NSString *repoURL, void (^completion)(BOOL success, NSString *message)) {
    NSURL *url = [NSURL URLWithString:repoURL];
    if (!url) { completion(NO, @"Invalid URL"); return; }
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) { 
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, error.localizedDescription); }); 
            return; 
        }
        
        NSError *jsonErr;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
        if (jsonErr || !json[@"tweaks"]) { 
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, @"Invalid JSON"); }); 
            return; 
        }
        
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        NSMutableDictionary *caches = [[d dictionaryForKey:@"RepoTweaksCaches"] mutableCopy] ?: [NSMutableDictionary dictionary];
        caches[repoURL] = json;
        [d setObject:caches forKey:@"RepoTweaksCaches"];
        
        NSMutableArray *urls = [[d arrayForKey:@"RepoTweaksURLs"] mutableCopy] ?: [NSMutableArray array];
        if (![urls containsObject:repoURL]) { 
            [urls addObject:repoURL]; 
            [d setObject:urls forKey:@"RepoTweaksURLs"]; 
        }
        [d synchronize];
        
        for (NSDictionary *t in json[@"tweaks"]) {
            repotweaks_download_script(t[@"id"], t[@"scriptURL"], ^(BOOL success) {});
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{ completion(YES, @"Refreshed"); });
    }] resume];
}

void repotweaks_download_script(NSString *tweakId, NSString *scriptURL, void (^completion)(BOOL success)) {
    NSURL *url = [NSURL URLWithString:scriptURL];
    if (!url) { completion(NO); return; }
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error && data) {
            NSString *jsCode = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (jsCode) {
                NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
                [d setObject:jsCode forKey:[NSString stringWithFormat:@"RepoTweakScript_%@", tweakId]];
                [d synchronize];
                dispatch_async(dispatch_get_main_queue(), ^{ completion(YES); });
                return;
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
    }] resume];
}

// =============================================================================
// teardown engine
// =============================================================================
bool repotweaks_stop_in_session(void) {
    __sync_lock_test_and_set(&g_repo_shutting_down, 1);
    
    if (!g_repo_ipc_lock) g_repo_ipc_lock = [[NSRecursiveLock alloc] init];
    
    [g_repo_ipc_lock lock];
    log_user("[RepoTweaks] Safe stop: Green light, stopping timers...\n");
    
    if (g_repo_timers_registry) {
        for (NSString *tweakID in g_repo_timers_registry) {
            NSMutableDictionary *timers = g_repo_timers_registry[tweakID];
            for (id timerSource in timers.allValues) {
                dispatch_source_cancel((dispatch_source_t)timerSource);
            }
            [timers removeAllObjects];
        }
        [g_repo_timers_registry removeAllObjects];
    }
    
    if (g_repo_contexts) {
        [g_repo_contexts removeAllObjects];
    }

    [g_repo_ipc_lock unlock];
    return true;
}
