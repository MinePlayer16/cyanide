//
//  SourcesViewController.m
//  Cyanide
//

#import "SourcesViewController.h"
#import "JSTweakDocsViewController.h"
#import "Package.h"
#import "PackageDetailViewController.h"
#import "PackageQueue.h"
#import "../tweaks/RepoTweaks.h"
#import "../tweaks/QuickLoader.h"

static NSString * const kSourceCellID      = @"SourceCell";
static NSString * const kSourcePkgCellID   = @"SourcePkgCell";

static NSString *sources_string_or_empty(id value)
{
    return [value isKindOfClass:NSString.class] ? (NSString *)value : @"";
}

static NSArray<NSString *> *sources_urls(void)
{
    id raw = [NSUserDefaults.standardUserDefaults objectForKey:@"RepoTweaksURLs"];
    if (![raw isKindOfClass:NSArray.class]) return @[];
    NSMutableArray<NSString *> *urls = [NSMutableArray array];
    for (id value in (NSArray *)raw) {
        if ([value isKindOfClass:NSString.class]) [urls addObject:value];
    }
    return urls;
}

static NSDictionary *sources_caches(void)
{
    id raw = [NSUserDefaults.standardUserDefaults objectForKey:@"RepoTweaksCaches"];
    return [raw isKindOfClass:NSDictionary.class] ? (NSDictionary *)raw : @{};
}

static NSDictionary *sources_repo_for_url(NSString *url)
{
    id repo = url.length ? sources_caches()[url] : nil;
    return [repo isKindOfClass:NSDictionary.class] ? (NSDictionary *)repo : @{};
}

static NSArray<NSDictionary *> *sources_tweaks_for_url(NSString *url)
{
    id raw = sources_repo_for_url(url)[@"tweaks"];
    if (![raw isKindOfClass:NSArray.class]) return @[];
    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
    for (id value in (NSArray *)raw) {
        if ([value isKindOfClass:NSDictionary.class]) [out addObject:value];
    }
    return out;
}

static Package *sources_package_for_tweak(NSString *url, NSDictionary *tweak)
{
    NSDictionary *repo = sources_repo_for_url(url);
    NSString *tweakID = sources_string_or_empty(tweak[@"id"]);
    NSString *identifier = [NSString stringWithFormat:@"repo.%@", repotweaks_storage_key(url, tweakID)];
    Package *pkg = [[Package alloc] initRepoTweakWithIdentifier:identifier
                                                           name:sources_string_or_empty(tweak[@"name"])
                                               shortDescription:sources_string_or_empty(tweak[@"description"])
                                                        version:sources_string_or_empty(tweak[@"version"])
                                                         author:sources_string_or_empty(repo[@"author"])
                                                       repoName:sources_string_or_empty(repo[@"repoName"])
                                                        repoURL:url
                                                    repoTweakID:tweakID
                                                   repoScriptURL:sources_string_or_empty(tweak[@"scriptURL"])];
    if ([[NSUserDefaults.standardUserDefaults stringForKey:repotweaks_script_defaults_key(url, tweakID)] length] == 0) {
        pkg.installDisabledReason = @"Refresh this source before installing.";
    }
    return pkg;
}

static BOOL sources_tweak_has_update(NSString *url, NSDictionary *tweak)
{
    NSString *tweakID = sources_string_or_empty(tweak[@"id"]);
    if (tweakID.length == 0) return NO;
    NSString *installed = [NSUserDefaults.standardUserDefaults stringForKey:repotweaks_installed_version_key(url, tweakID)];
    if (!installed.length) return NO;
    NSString *repoVersion = sources_string_or_empty(tweak[@"version"]);
    if (!repoVersion.length) return NO;
    return [repoVersion compare:installed options:NSNumericSearch] == NSOrderedDescending;
}

static NSUInteger sources_update_count_for_url(NSString *url)
{
    NSUInteger count = 0;
    for (NSDictionary *tweak in sources_tweaks_for_url(url)) {
        if (sources_tweak_has_update(url, tweak)) count++;
    }
    return count;
}

static void sources_clear_repo_defaults(NSString *url)
{
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    for (NSDictionary *tweak in sources_tweaks_for_url(url)) {
        NSString *tweakID = sources_string_or_empty(tweak[@"id"]);
        if (tweakID.length == 0) continue;
        [d removeObjectForKey:repotweaks_enabled_defaults_key(url, tweakID)];
        [d removeObjectForKey:repotweaks_script_defaults_key(url, tweakID)];
        [d removeObjectForKey:repotweaks_values_defaults_key(url, tweakID)];
        repotweaks_cancel_tweak(url, tweakID);
        quickloader_clear_repo_tweak_if_matches(url, tweakID);
    }
}

#pragma mark - Source Packages (drill-down)

@interface SourcePackagesViewController : UITableViewController
@property (nonatomic, copy) NSString *repoURL;
@end

@implementation SourcePackagesViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    NSDictionary *repo = sources_repo_for_url(self.repoURL);
    NSString *name = sources_string_or_empty(repo[@"repoName"]);
    self.title = name.length ? name : @"Source";
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 68.0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)sources_tweaks_for_url(self.repoURL).count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kSourcePkgCellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kSourcePkgCellID];
    }
    NSArray *tweaks = sources_tweaks_for_url(self.repoURL);
    if (indexPath.row >= (NSInteger)tweaks.count) return cell;
    NSDictionary *tweak = tweaks[indexPath.row];

    UIListContentConfiguration *config = [UIListContentConfiguration subtitleCellConfiguration];
    config.image = [UIImage systemImageNamed:@"bolt.fill"];
    config.imageProperties.preferredSymbolConfiguration =
        [UIImageSymbolConfiguration configurationWithPointSize:18.0 weight:UIImageSymbolWeightSemibold];
    config.imageProperties.tintColor = UIColor.systemOrangeColor;
    config.imageProperties.reservedLayoutSize = CGSizeMake(34.0, 28.0);
    config.imageProperties.maximumSize = CGSizeMake(28.0, 28.0);
    config.imageToTextPadding = 14.0;
    config.text = sources_string_or_empty(tweak[@"name"]);
    config.textProperties.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    NSString *version = sources_string_or_empty(tweak[@"version"]);
    NSString *desc = sources_string_or_empty(tweak[@"description"]);
    config.secondaryText = version.length ? [NSString stringWithFormat:@"v%@ · %@", version, desc] : desc;
    config.secondaryTextProperties.color = UIColor.secondaryLabelColor;
    config.secondaryTextProperties.numberOfLines = 2;
    config.textToSecondaryTextVerticalPadding = 3.0;
    NSDirectionalEdgeInsets m = config.directionalLayoutMargins;
    m.top = 12.0; m.bottom = 12.0;
    config.directionalLayoutMargins = m;
    cell.contentConfiguration = config;

    if (sources_tweak_has_update(self.repoURL, tweak)) {
        UILabel *pill = [[UILabel alloc] init];
        pill.text = @"UPDATE";
        pill.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightHeavy];
        pill.textColor = UIColor.systemBlueColor;
        pill.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.15];
        pill.textAlignment = NSTextAlignmentCenter;
        [pill sizeToFit];
        CGRect f = pill.frame;
        f.size.width += 14.0;
        f.size.height = 22.0;
        pill.frame = f;
        pill.layer.cornerRadius = f.size.height / 2.0;
        pill.layer.cornerCurve = kCACornerCurveContinuous;
        pill.layer.masksToBounds = YES;
        cell.accessoryView = pill;
    } else {
        cell.accessoryView = nil;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSArray *tweaks = sources_tweaks_for_url(self.repoURL);
    if (indexPath.row >= (NSInteger)tweaks.count) return;
    Package *pkg = sources_package_for_tweak(self.repoURL, tweaks[indexPath.row]);
    PackageDetailViewController *detail = [[PackageDetailViewController alloc] initWithPackage:pkg];
    [self.navigationController pushViewController:detail animated:YES];
}

@end

#pragma mark - Sources list

@interface SourcesViewController ()
@property (nonatomic, copy) NSArray<NSString *> *urls;
@end

@implementation SourcesViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Sources";
    self.navigationItem.title = @"Sources";
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 72.0;

    UIBarButtonItem *add = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                         target:self
                                                                         action:@selector(addSource)];
    UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                             target:self
                                                                             action:@selector(refreshAll)];
    self.navigationItem.rightBarButtonItems = @[add, refresh];

    repotweaks_seed_default_repos();
    [self reloadSources];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(sourcesDidRefresh:)
                                                 name:RepoTweaksDidRefreshNotification
                                               object:nil];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)sourcesDidRefresh:(NSNotification *)note
{
    if (!self.isViewLoaded) return;
    [self reloadSources];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self reloadSources];
}

- (void)reloadSources
{
    self.urls = sources_urls();
    [self.tableView reloadData];
}

- (void)showDocsForMode:(JSTweakDocsMode)mode
{
    JSTweakDocsViewController *docs = [[JSTweakDocsViewController alloc] init];
    docs.docsMode = mode;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:docs];
    nav.navigationBar.barStyle = UIBarStyleBlack;
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

- (UITableViewCell *)docCellForRow:(NSInteger)row tableView:(UITableView *)tableView
{
    static NSString *kDocCellID = @"DocCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kDocCellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kDocCellID];
    }

    UIListContentConfiguration *config = [UIListContentConfiguration subtitleCellConfiguration];
    config.imageProperties.preferredSymbolConfiguration =
        [UIImageSymbolConfiguration configurationWithPointSize:18.0 weight:UIImageSymbolWeightSemibold];
    config.imageProperties.reservedLayoutSize = CGSizeMake(34.0, 28.0);
    config.imageProperties.maximumSize = CGSizeMake(28.0, 28.0);
    config.imageToTextPadding = 14.0;
    config.textProperties.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    config.secondaryTextProperties.color = UIColor.secondaryLabelColor;
    config.textToSecondaryTextVerticalPadding = 2.0;
    NSDirectionalEdgeInsets m = config.directionalLayoutMargins;
    m.top = 12.0; m.bottom = 12.0;
    config.directionalLayoutMargins = m;

    if (row == 0) {
        config.image = [UIImage systemImageNamed:@"hammer.fill"];
        config.imageProperties.tintColor = UIColor.systemOrangeColor;
        config.text = @"Build Your Own JS Tweak";
        config.secondaryText = @"Write scripts, declare parameters, use the RemoteCall API";
    } else {
        config.image = [UIImage systemImageNamed:@"server.rack"];
        config.imageProperties.tintColor = UIColor.systemIndigoColor;
        config.text = @"Set Up a Tweak Repository";
        config.secondaryText = @"Host a JSON feed on GitHub Pages or any HTTPS server";
    }

    cell.contentConfiguration = config;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)addSource
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Add Source"
                                                                   message:@"Paste an HTTPS RepoTweaks JSON URL."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"https://example.com/packages.json";
        tf.keyboardType = UIKeyboardTypeURL;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Add" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        NSString *url = alert.textFields.firstObject.text ?: @"";
        repotweaks_refresh_repo(url, ^(BOOL success, NSString *message) {
            [self reloadSources];
            [[NSNotificationCenter defaultCenter] postNotificationName:RepoTweaksDidRefreshNotification object:nil];
            if (!success) [self presentError:message ?: @"Could not refresh that source."];
        });
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)refreshAll
{
    NSArray<NSString *> *urls = sources_urls();
    if (urls.count == 0) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Refreshing Sources"
                                                                   message:@"Downloading package lists and scripts…"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:alert animated:YES completion:nil];

    dispatch_group_t group = dispatch_group_create();
    __block NSString *firstError = nil;
    for (NSString *url in urls) {
        dispatch_group_enter(group);
        repotweaks_refresh_repo(url, ^(BOOL success, NSString *message) {
            if (!success && firstError.length == 0) firstError = message;
            dispatch_group_leave(group);
        });
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        [alert dismissViewControllerAnimated:YES completion:^{
            [self reloadSources];
            [[NSNotificationCenter defaultCenter] postNotificationName:RepoTweaksDidRefreshNotification object:nil];
            if (firstError.length > 0) [self presentError:firstError];
        }];
    });
}

- (void)presentError:(NSString *)message
{
    UIAlertController *err = [UIAlertController alertControllerWithTitle:@"Source Failed"
                                                                 message:message ?: @"Could not refresh source."
                                                          preferredStyle:UIAlertControllerStyleAlert];
    [err addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:err animated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (section == 0) return self.urls.count > 0 ? @"Repositories" : nil;
    return @"Developer";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (section == 0) {
        if (self.urls.count == 0) return @"No sources added yet. Tap + to add an HTTPS RepoTweaks JSON URL.";
        return @"Swipe left to remove a source.";
    }
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == 0) return (NSInteger)self.urls.count;
    return 2;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 1) return [self docCellForRow:indexPath.row tableView:tableView];

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kSourceCellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kSourceCellID];
    }
    if (indexPath.row >= (NSInteger)self.urls.count) return cell;
    NSString *url = self.urls[indexPath.row];
    NSDictionary *repo = sources_repo_for_url(url);
    NSArray *tweaks = sources_tweaks_for_url(url);
    NSString *repoName = sources_string_or_empty(repo[@"repoName"]);
    NSString *author = sources_string_or_empty(repo[@"author"]);

    UIListContentConfiguration *config = [UIListContentConfiguration subtitleCellConfiguration];
    config.image = [UIImage systemImageNamed:@"tray.and.arrow.down.fill"];
    config.imageProperties.preferredSymbolConfiguration =
        [UIImageSymbolConfiguration configurationWithPointSize:20.0 weight:UIImageSymbolWeightSemibold];
    config.imageProperties.tintColor = UIColor.systemGreenColor;
    config.imageProperties.reservedLayoutSize = CGSizeMake(34.0, 28.0);
    config.imageProperties.maximumSize = CGSizeMake(28.0, 28.0);
    config.imageToTextPadding = 14.0;
    config.text = repoName.length ? repoName : @"Unknown Source";
    config.textProperties.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];

    NSUInteger updates = sources_update_count_for_url(url);
    NSMutableString *detail = [NSMutableString string];
    if (author.length) [detail appendFormat:@"%@ · ", author];
    [detail appendFormat:@"%lu package%@", (unsigned long)tweaks.count, tweaks.count == 1 ? @"" : @"s"];
    if (updates > 0) [detail appendFormat:@" · %lu update%@", (unsigned long)updates, updates == 1 ? @"" : @"s"];
    config.secondaryText = detail;
    config.secondaryTextProperties.color = updates > 0 ? UIColor.systemBlueColor : UIColor.secondaryLabelColor;
    config.textToSecondaryTextVerticalPadding = 3.0;

    NSDirectionalEdgeInsets m = config.directionalLayoutMargins;
    m.top = 14.0; m.bottom = 14.0;
    config.directionalLayoutMargins = m;
    cell.contentConfiguration = config;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) {
        [self showDocsForMode:(indexPath.row == 0) ? JSTweakDocsModeWriteTweak : JSTweakDocsModeSetupRepo];
        return;
    }
    if (indexPath.row >= (NSInteger)self.urls.count) return;
    SourcePackagesViewController *detail = [[SourcePackagesViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    detail.repoURL = self.urls[indexPath.row];
    [self.navigationController pushViewController:detail animated:YES];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    return indexPath.section == 0;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    if (indexPath.row >= (NSInteger)self.urls.count) return;

    NSString *url = self.urls[indexPath.row];
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    sources_clear_repo_defaults(url);

    NSMutableArray *urls = [sources_urls() mutableCopy];
    [urls removeObject:url];
    [d setObject:urls forKey:@"RepoTweaksURLs"];

    NSMutableDictionary *caches = [sources_caches() mutableCopy];
    [caches removeObjectForKey:url];
    [d setObject:caches forKey:@"RepoTweaksCaches"];
    [d synchronize];
    [self reloadSources];
}

@end
