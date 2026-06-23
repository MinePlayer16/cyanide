//
//  RepoTweaks.h
//

#ifndef RepoTweaks_h
#define RepoTweaks_h

#import <stdbool.h>
#import <Foundation/Foundation.h>

// Runs all enabled tweaks during the RUN 4/4 sequence
bool repotweaks_apply_in_session(void);

// Fetches the JSON from the given URL and caches it
void repotweaks_refresh_repo(NSString *repoURL, void (^completion)(BOOL success, NSString *message));

NSString *repotweaks_storage_key(NSString *repoURL, NSString *tweakId);
NSString *repotweaks_enabled_defaults_key(NSString *repoURL, NSString *tweakId);
NSString *repotweaks_script_defaults_key(NSString *repoURL, NSString *tweakId);
NSString *repotweaks_values_defaults_key(NSString *repoURL, NSString *tweakId);

// Downloads the raw .js code for a specific repository tweak
void repotweaks_download_script(NSString *repoURL, NSString *tweakId, NSString *scriptURL, void (^completion)(BOOL success));
void repotweaks_cancel_tweak(NSString *repoURL, NSString *tweakId);

bool repotweaks_stop_in_session(void);

#endif /* RepoTweaks_h */
