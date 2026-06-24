//
//  PackagesViewController.m
//  Cyanide
//

#import "PackagesViewController.h"
#import "PackageCatalog.h"
#import "PackageDetailViewController.h"
#import "PackageQueue.h"
#import "CategoryPackagesViewController.h"
#import "../SettingsViewController.h"

static NSString * const kCategoryCellID = @"CategoryCell";
static NSString * const kSearchPkgCellID = @"SearchPkgCell";

typedef struct {
    __unsafe_unretained NSString *name;
    __unsafe_unretained NSString *icon;
    __unsafe_unretained UIColor  *color;
} CategoryMeta;

static NSString *category_icon(NSString *cat)
{
    static NSDictionary<NSString *, NSString *> *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"Status Bar":          @"chart.bar.fill",
            @"Home Screen Layout":  @"square.grid.3x3.fill",
            @"Performance":         @"bolt.slash.fill",
            @"SpringBoard Tweaks":  @"sparkle",
            @"System Updates":      @"icloud.slash.fill",
            @"System":              @"gear",
            @"Beta":                @"testtube.2",
            @"Experimental":        @"flask.fill",
            @"In Development":      @"hammer.fill",
            @"JavaScript Tweaks":   @"bolt.fill",
        };
    });
    return map[cat] ?: @"shippingbox.fill";
}

static UIColor *category_color(NSString *cat)
{
    static NSDictionary<NSString *, UIColor *> *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"Status Bar":          UIColor.systemTealColor,
            @"Home Screen Layout":  UIColor.systemBlueColor,
            @"Performance":         UIColor.systemOrangeColor,
            @"SpringBoard Tweaks":  UIColor.systemCyanColor,
            @"System Updates":      UIColor.systemIndigoColor,
            @"System":              UIColor.systemGrayColor,
            @"Beta":                UIColor.systemPurpleColor,
            @"Experimental":        UIColor.systemRedColor,
            @"In Development":      UIColor.systemPurpleColor,
            @"JavaScript Tweaks":   UIColor.systemOrangeColor,
        };
    });
    return map[cat] ?: UIColor.secondaryLabelColor;
}

@interface PackagesViewController () <UISearchResultsUpdating>
@property (nonatomic, copy) NSArray<NSString *> *categories;
@property (nonatomic, copy) NSDictionary<NSString *, NSArray<Package *> *> *packagesByCategory;
@property (nonatomic, copy) NSArray<Package *> *allPackagesSorted;
@property (nonatomic, copy) NSArray<Package *> *searchResults;
@property (nonatomic, copy) NSString *searchText;
@property (nonatomic, strong) UISearchController *searchCtl;
@end

@implementation PackagesViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Packages";
    self.navigationItem.title = @"Packages";
    self.searchText = @"";

    [self refreshCatalog];

    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 72.0;
    self.tableView.sectionFooterHeight = 4.0;
    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 0.0;
    }

    self.searchCtl = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchCtl.searchResultsUpdater = self;
    self.searchCtl.obscuresBackgroundDuringPresentation = NO;
    self.searchCtl.searchBar.placeholder = @"Search all tweaks";
    self.navigationItem.searchController = self.searchCtl;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(catalogDidChange:)
                                                 name:PackageQueueDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(catalogDidChange:)
                                                 name:kSettingsActionsDidCompleteNotification
                                               object:nil];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self refreshCatalog];
    [self.tableView reloadData];
}

- (void)catalogDidChange:(NSNotification *)note
{
    if (!self.isViewLoaded) return;
    [self refreshCatalog];
    [self.tableView reloadData];
}

- (void)refreshCatalog
{
    self.allPackagesSorted = [[PackageCatalog allPackages]
        sortedArrayUsingComparator:^NSComparisonResult(Package *a, Package *b) {
            return [a.name caseInsensitiveCompare:b.name];
        }];

    NSMutableArray<NSString *> *cats = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSMutableArray<Package *> *> *buckets = [NSMutableDictionary dictionary];
    for (NSString *cat in [PackageCatalog categoriesInOrder]) {
        NSMutableArray *inCat = [NSMutableArray array];
        for (Package *p in self.allPackagesSorted) {
            if ([p.category isEqualToString:cat]) [inCat addObject:p];
        }
        if (inCat.count > 0) {
            [cats addObject:cat];
            buckets[cat] = inCat;
        }
    }
    self.categories = cats;
    self.packagesByCategory = buckets;

    [self rebuildSearchResults];
}

- (BOOL)isSearchActive
{
    return self.searchText.length > 0;
}

#pragma mark - Search

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController
{
    NSString *q = searchController.searchBar.text ?: @"";
    if ([q isEqualToString:self.searchText]) return;
    self.searchText = q;
    [self rebuildSearchResults];
    [self.tableView reloadData];
}

- (void)rebuildSearchResults
{
    if (![self isSearchActive]) {
        self.searchResults = nil;
        return;
    }
    NSString *q = self.searchText;
    NSStringCompareOptions opt = NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch;
    NSMutableArray *out = [NSMutableArray array];
    for (Package *p in self.allPackagesSorted) {
        if ([p.name rangeOfString:q options:opt].location != NSNotFound ||
            [p.shortDescription rangeOfString:q options:opt].location != NSNotFound ||
            [p.category rangeOfString:q options:opt].location != NSNotFound) {
            [out addObject:p];
        }
    }
    self.searchResults = out;
}

#pragma mark - Data source

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if ([self isSearchActive]) return (NSInteger)self.searchResults.count;
    return (NSInteger)self.categories.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if ([self isSearchActive]) return [self searchCellForRowAtIndexPath:indexPath tableView:tableView];
    return [self categoryCellForRowAtIndexPath:indexPath tableView:tableView];
}

- (UITableViewCell *)categoryCellForRowAtIndexPath:(NSIndexPath *)indexPath tableView:(UITableView *)tableView
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCategoryCellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kCategoryCellID];
    }

    NSString *cat = self.categories[indexPath.row];
    NSArray<Package *> *pkgs = self.packagesByCategory[cat];
    NSUInteger count = pkgs.count;

    UIListContentConfiguration *config = [UIListContentConfiguration subtitleCellConfiguration];
    config.image = [UIImage systemImageNamed:category_icon(cat)];
    config.imageProperties.preferredSymbolConfiguration =
        [UIImageSymbolConfiguration configurationWithPointSize:20.0 weight:UIImageSymbolWeightSemibold];
    config.imageProperties.tintColor = category_color(cat);
    config.imageProperties.reservedLayoutSize = CGSizeMake(34.0, 28.0);
    config.imageProperties.maximumSize = CGSizeMake(28.0, 28.0);
    config.imageToTextPadding = 14.0;
    config.text = cat;
    config.textProperties.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];

    NSMutableArray<NSString *> *names = [NSMutableArray array];
    NSUInteger limit = MIN(count, (NSUInteger)3);
    for (NSUInteger i = 0; i < limit; i++) [names addObject:pkgs[i].name];
    NSString *preview = [names componentsJoinedByString:@", "];
    if (count > 3) preview = [preview stringByAppendingFormat:@" +%lu more", (unsigned long)(count - 3)];

    config.secondaryText = [NSString stringWithFormat:@"%lu package%@ · %@",
                            (unsigned long)count, count == 1 ? @"" : @"s", preview];
    config.secondaryTextProperties.color = UIColor.secondaryLabelColor;
    config.secondaryTextProperties.numberOfLines = 2;
    config.textToSecondaryTextVerticalPadding = 3.0;

    NSDirectionalEdgeInsets m = config.directionalLayoutMargins;
    m.top = 14.0; m.bottom = 14.0;
    config.directionalLayoutMargins = m;
    cell.contentConfiguration = config;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.accessoryView = nil;
    return cell;
}

- (UITableViewCell *)searchCellForRowAtIndexPath:(NSIndexPath *)indexPath tableView:(UITableView *)tableView
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kSearchPkgCellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kSearchPkgCellID];
    }
    Package *pkg = self.searchResults[indexPath.row];

    UIListContentConfiguration *config = [UIListContentConfiguration subtitleCellConfiguration];
    config.image = [UIImage systemImageNamed:pkg.symbolName];
    config.imageProperties.preferredSymbolConfiguration =
        [UIImageSymbolConfiguration configurationWithPointSize:22.0 weight:UIImageSymbolWeightRegular];
    config.imageProperties.tintColor = pkg.isInstallDisabled ? UIColor.secondaryLabelColor : self.view.tintColor;
    config.imageProperties.reservedLayoutSize = CGSizeMake(34.0, 28.0);
    config.imageProperties.maximumSize = CGSizeMake(28.0, 28.0);
    config.imageToTextPadding = 14.0;
    config.text = pkg.name;
    config.textProperties.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    if (pkg.isInstallDisabled) config.textProperties.color = UIColor.secondaryLabelColor;
    config.secondaryText = [NSString stringWithFormat:@"%@ · %@", pkg.category, pkg.shortDescription];
    config.secondaryTextProperties.color = UIColor.secondaryLabelColor;
    config.secondaryTextProperties.numberOfLines = 2;
    config.textToSecondaryTextVerticalPadding = 3.0;
    NSDirectionalEdgeInsets m = config.directionalLayoutMargins;
    m.top = 14.0; m.bottom = 14.0;
    config.directionalLayoutMargins = m;
    cell.contentConfiguration = config;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.accessoryView = nil;
    return cell;
}

#pragma mark - Delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if ([self isSearchActive]) {
        Package *pkg = self.searchResults[indexPath.row];
        PackageDetailViewController *detail = [[PackageDetailViewController alloc] initWithPackage:pkg];
        [self.navigationController pushViewController:detail animated:YES];
        return;
    }

    NSString *cat = self.categories[indexPath.row];
    CategoryPackagesViewController *list = [[CategoryPackagesViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    list.categoryName = cat;
    [self.navigationController pushViewController:list animated:YES];
}

@end
