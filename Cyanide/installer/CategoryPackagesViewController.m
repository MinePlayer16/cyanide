//
//  CategoryPackagesViewController.m
//  Cyanide
//

#import "CategoryPackagesViewController.h"
#import "PackageCatalog.h"
#import "PackageDetailViewController.h"
#import "PackageQueue.h"
#import "../SettingsViewController.h"

static NSString * const kCatPkgCellID = @"CatPkgCell";

@interface CategoryPackagesViewController () <UISearchResultsUpdating>
@property (nonatomic, copy) NSArray<Package *> *allPackages;
@property (nonatomic, copy) NSArray<Package *> *filteredPackages;
@property (nonatomic, copy) NSString *searchText;
@property (nonatomic, strong) UISearchController *searchCtl;
@end

@implementation CategoryPackagesViewController

- (BOOL)packageNeedsThemeBeforeInstall:(Package *)pkg
{
    return [pkg.identifier isEqualToString:@"com.darksword.themer"] &&
           !pkg.isInstalled &&
           !settings_themer_has_selected_theme();
}

- (BOOL)packageNeedsLiveWPVideoBeforeInstall:(Package *)pkg
{
    return [pkg.identifier isEqualToString:@"com.darksword.livewp"] &&
           !pkg.isInstalled &&
           ![SettingsViewController liveWPHasSelectedVideo];
}

- (BOOL)presentQueueConflictIfNeededForPackage:(Package *)pkg intent:(PackageQueueIntent)intent
{
    NSString *reason = nil;
    if ([[PackageQueue sharedQueue] canQueueIntent:intent forPackage:pkg reason:&reason]) return NO;
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Run Hide Home Bar Alone"
                                            message:reason ?: @"Hide Home Bar must be the only pending queue item."
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
    return YES;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = self.categoryName ?: @"Packages";
    self.searchText = @"";

    [self refreshPackages];

    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 68.0;

    self.searchCtl = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchCtl.searchResultsUpdater = self;
    self.searchCtl.obscuresBackgroundDuringPresentation = NO;
    self.searchCtl.searchBar.placeholder = @"Search";
    self.navigationItem.searchController = self.searchCtl;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(queueDidChange:)
                                                 name:PackageQueueDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(queueDidChange:)
                                                 name:kSettingsActionsDidCompleteNotification
                                               object:nil];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self refreshPackages];
    [self.tableView reloadData];
}

- (void)refreshPackages
{
    NSString *cat = self.categoryName;
    NSArray<Package *> *all = [[PackageCatalog allPackages]
        sortedArrayUsingComparator:^NSComparisonResult(Package *a, Package *b) {
            return [a.name caseInsensitiveCompare:b.name];
        }];
    if (cat.length > 0) {
        NSMutableArray *filtered = [NSMutableArray array];
        for (Package *p in all) {
            if ([p.category isEqualToString:cat]) [filtered addObject:p];
        }
        self.allPackages = filtered;
    } else {
        self.allPackages = all;
    }
    [self rebuildFiltered];
}

- (void)queueDidChange:(NSNotification *)note
{
    if (!self.isViewLoaded) return;
    [self refreshPackages];
    [self.tableView reloadData];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController
{
    NSString *q = searchController.searchBar.text ?: @"";
    if ([q isEqualToString:self.searchText]) return;
    self.searchText = q;
    [self rebuildFiltered];
    [self.tableView reloadData];
}

- (void)rebuildFiltered
{
    if (self.searchText.length == 0) {
        self.filteredPackages = self.allPackages;
        return;
    }
    NSString *q = self.searchText;
    NSStringCompareOptions opt = NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch;
    NSMutableArray *out = [NSMutableArray array];
    for (Package *p in self.allPackages) {
        if ([p.name rangeOfString:q options:opt].location != NSNotFound ||
            [p.shortDescription rangeOfString:q options:opt].location != NSNotFound) {
            [out addObject:p];
        }
    }
    self.filteredPackages = out;
}

#pragma mark - Data source

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)self.filteredPackages.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCatPkgCellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kCatPkgCellID];
    }
    Package *pkg = self.filteredPackages[indexPath.row];

    UIListContentConfiguration *config = [UIListContentConfiguration subtitleCellConfiguration];
    config.image = [UIImage systemImageNamed:pkg.symbolName];
    config.imageProperties.preferredSymbolConfiguration =
        [UIImageSymbolConfiguration configurationWithPointSize:22.0 weight:UIImageSymbolWeightRegular];
    UIColor *mainColor = pkg.isInstallDisabled ? UIColor.secondaryLabelColor : self.view.tintColor;
    config.imageProperties.tintColor = mainColor;
    config.imageProperties.reservedLayoutSize = CGSizeMake(34.0, 28.0);
    config.imageProperties.maximumSize = CGSizeMake(28.0, 28.0);
    config.imageToTextPadding = 14.0;
    config.text = pkg.name;
    config.textProperties.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    if (pkg.isInstallDisabled) config.textProperties.color = UIColor.secondaryLabelColor;
    config.secondaryText = pkg.shortDescription;
    config.secondaryTextProperties.color = pkg.isInstallDisabled ? UIColor.tertiaryLabelColor : UIColor.secondaryLabelColor;
    config.secondaryTextProperties.numberOfLines = 2;
    config.textToSecondaryTextVerticalPadding = 3.0;
    NSDirectionalEdgeInsets m = config.directionalLayoutMargins;
    m.top = 14.0; m.bottom = 14.0;
    config.directionalLayoutMargins = m;
    cell.contentConfiguration = config;

    cell.accessoryView = [self accessoryViewForPackage:pkg];
    cell.accessoryType = cell.accessoryView ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

#pragma mark - Accessory pills

- (UIView *)accessoryViewForPackage:(Package *)pkg
{
    PackageQueueIntent intent = [[PackageQueue sharedQueue] intentForPackage:pkg];
    if (pkg.kind == PackageInstallKindDirectTool ||
        ((pkg.kind == PackageInstallKindOTA || pkg.kind == PackageInstallKindNanoRegistry ||
          pkg.kind == PackageInstallKindCallRecordingSound || pkg.kind == PackageInstallKindHideHomeBar)
         && intent == PackageQueueIntentNone)) {
        if (intent != PackageQueueIntentNone) {
            return [self pillWithText:@"PENDING" background:[self.view.tintColor colorWithAlphaComponent:0.18] textColor:self.view.tintColor];
        }
        return [self pillWithText:@"MANUAL" background:[UIColor.secondaryLabelColor colorWithAlphaComponent:0.14] textColor:UIColor.secondaryLabelColor];
    }
    if (pkg.kind == PackageInstallKindRepoTweak) {
        if (intent != PackageQueueIntentNone) {
            NSString *t = (intent == PackageQueueIntentInstall) ? @"WILL INSTALL" : @"WILL REMOVE";
            return [self pillWithText:t background:[self.view.tintColor colorWithAlphaComponent:0.18] textColor:self.view.tintColor];
        }
        if (pkg.isInstalled)
            return [self pillWithText:@"INSTALLED" background:[UIColor colorWithRed:0.16 green:0.55 blue:0.32 alpha:0.18] textColor:UIColor.systemGreenColor];
        if (pkg.isInstallDisabled) {
            NSString *label = [pkg.installDisabledReason containsString:@"Refresh"] ? @"REFRESH" : @"DISABLED";
            return [self pillWithText:label background:[[UIColor systemOrangeColor] colorWithAlphaComponent:0.16] textColor:UIColor.systemOrangeColor];
        }
    }
    if (intent != PackageQueueIntentNone) {
        NSString *t = (intent == PackageQueueIntentInstall) ? @"WILL ACTIVATE" : @"WILL DEACTIVATE";
        return [self pillWithText:t background:[self.view.tintColor colorWithAlphaComponent:0.18] textColor:self.view.tintColor];
    }
    if (pkg.isInstalled)
        return [self pillWithText:@"INSTALLED" background:[UIColor colorWithRed:0.16 green:0.55 blue:0.32 alpha:0.18] textColor:UIColor.systemGreenColor];
    if (pkg.isInstallDisabled)
        return [self pillWithText:@"DISABLED" background:[[UIColor systemRedColor] colorWithAlphaComponent:0.16] textColor:UIColor.systemRedColor];
    if (pkg.creatorOnly)
        return [self pillWithText:@"IN DEV" background:[[UIColor systemPurpleColor] colorWithAlphaComponent:0.16] textColor:UIColor.systemPurpleColor];
    if (pkg.experimental)
        return [self pillWithText:@"EXPERIMENTAL" background:[[UIColor systemRedColor] colorWithAlphaComponent:0.18] textColor:UIColor.systemRedColor];
    if ([pkg.category caseInsensitiveCompare:@"Beta"] == NSOrderedSame)
        return [self pillWithText:@"BETA" background:[[UIColor systemPurpleColor] colorWithAlphaComponent:0.18] textColor:UIColor.systemPurpleColor];
    if (pkg.isNew)
        return [self pillWithText:@"NEW" background:[UIColor colorWithRed:0.95 green:0.55 blue:0.05 alpha:0.18] textColor:UIColor.systemOrangeColor];
    return nil;
}

- (UIView *)pillWithText:(NSString *)text background:(UIColor *)bg textColor:(UIColor *)fg
{
    UILabel *pill = [[UILabel alloc] init];
    pill.text = text;
    pill.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightHeavy];
    pill.textColor = fg;
    pill.backgroundColor = bg;
    pill.textAlignment = NSTextAlignmentCenter;
    [pill sizeToFit];
    CGRect f = pill.frame;
    f.size.width += 14.0;
    f.size.height = 22.0;
    pill.frame = f;
    pill.layer.cornerRadius = f.size.height / 2.0;
    pill.layer.cornerCurve = kCACornerCurveContinuous;
    pill.layer.masksToBounds = YES;
    return pill;
}

#pragma mark - Delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    Package *pkg = self.filteredPackages[indexPath.row];
    PackageDetailViewController *detail = [[PackageDetailViewController alloc] initWithPackage:pkg];
    [self.navigationController pushViewController:detail animated:YES];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath
{
    Package *pkg = self.filteredPackages[indexPath.row];
    PackageQueue *q = [PackageQueue sharedQueue];
    PackageQueueIntent intent = [q intentForPackage:pkg];

    if (pkg.kind == PackageInstallKindDirectTool) {
        UIContextualAction *open = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"Open" handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
            done(YES);
            [self navigateToSettingsSectionForPackage:pkg];
        }];
        open.backgroundColor = self.view.tintColor;
        open.image = [UIImage systemImageNamed:@"slider.horizontal.3"];
        UISwipeActionsConfiguration *cfg = [UISwipeActionsConfiguration configurationWithActions:@[open]];
        cfg.performsFirstActionWithFullSwipe = YES;
        return cfg;
    }
    if (pkg.isInstallDisabled && !pkg.isInstalled && intent == PackageQueueIntentNone) return nil;

    NSString *title;
    UIColor *color;
    NSString *symbol;
    if (intent != PackageQueueIntentNone) {
        title = @"Cancel"; color = UIColor.systemGrayColor; symbol = @"xmark.circle";
    } else if (pkg.isInstalled) {
        title = (pkg.kind == PackageInstallKindRepoTweak) ? @"Remove" : @"Deactivate";
        color = UIColor.systemRedColor; symbol = @"power";
    } else if ([self packageNeedsThemeBeforeInstall:pkg]) {
        title = @"Select Theme"; color = self.view.tintColor; symbol = @"paintpalette";
    } else if ([self packageNeedsLiveWPVideoBeforeInstall:pkg]) {
        title = @"Select Video"; color = self.view.tintColor; symbol = @"photo.badge.plus";
    } else {
        title = (pkg.kind == PackageInstallKindRepoTweak) ? @"Install" : @"Activate";
        color = self.view.tintColor; symbol = @"play.circle";
    }

    UIContextualAction *action = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:title handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        BOOL isInstall = (intent == PackageQueueIntentNone && !pkg.isInstalled);
        BOOL isUninstall = (intent == PackageQueueIntentNone && pkg.isInstalled);
        if (isInstall && [self packageNeedsThemeBeforeInstall:pkg]) { done(YES); return; }
        if (isInstall && [self packageNeedsLiveWPVideoBeforeInstall:pkg]) { done(YES); [self navigateToSettingsSectionForPackage:pkg]; return; }
        if (isInstall && [self presentQueueConflictIfNeededForPackage:pkg intent:PackageQueueIntentInstall]) { done(YES); return; }
        if (isUninstall && [self presentQueueConflictIfNeededForPackage:pkg intent:PackageQueueIntentUninstall]) { done(YES); return; }
        [q toggleForPackage:pkg];
        done(YES);
    }];
    action.backgroundColor = color;
    action.image = [UIImage systemImageNamed:symbol];
    UISwipeActionsConfiguration *cfg = [UISwipeActionsConfiguration configurationWithActions:@[action]];
    cfg.performsFirstActionWithFullSwipe = YES;
    return cfg;
}

- (void)navigateToSettingsSectionForPackage:(Package *)pkg
{
    UITabBarController *tab = self.tabBarController;
    NSUInteger settingsIndex = NSNotFound;
    UINavigationController *settingsNav = nil;
    for (NSUInteger i = 0; i < tab.viewControllers.count; i++) {
        UIViewController *vc = tab.viewControllers[i];
        if ([vc.tabBarItem.title isEqualToString:@"Settings"]) {
            settingsIndex = i;
            if ([vc isKindOfClass:UINavigationController.class]) settingsNav = (UINavigationController *)vc;
            break;
        }
    }
    if (settingsIndex == NSNotFound || !settingsNav) return;
    [settingsNav popToRootViewControllerAnimated:NO];
    SettingsViewController *bundle = [[SettingsViewController alloc] initWithUnderlyingSection:pkg.settingsSection bundleTitle:pkg.name];
    bundle.installerReturnPackageName = pkg.name;
    [settingsNav pushViewController:bundle animated:NO];
    tab.selectedIndex = settingsIndex;
}

@end
