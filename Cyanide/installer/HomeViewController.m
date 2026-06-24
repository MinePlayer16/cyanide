//
//  HomeViewController.m
//  Cyanide
//

#import "HomeViewController.h"
#import "SourcesViewController.h"
#import "../SettingsViewController.h"
#import "../tweaks/RepoTweaks.h"

static NSString * const kSignalGroupURL  = @"https://signal.group/#CjQKIP0pxjc9V52ddCNk--04DosuoQl-vVOsznJfQ4GwlrlxEhCveFhBS8YdNcILpUFt7IqC";
static NSString * const kGitHubIssuesURL = @"https://github.com/zeroxjf/cyanide/issues";
static NSString * const kGitHubRepoURL   = @"https://github.com/zeroxjf/cyanide";
static NSString * const kPatreonURL      = @"https://www.patreon.com/zeroxjf";

static const CGFloat kPad    = 16.0;
static const CGFloat kMargin = 20.0;
static const CGFloat kGap    = 20.0;

@interface HomeViewController ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *stack;
@end

@implementation HomeViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Home";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.navigationController.navigationBar.prefersLargeTitles = YES;

    NSString *ver = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
    self.navigationItem.title = [NSString stringWithFormat:@"Cyanide v%@", ver];

    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:self.scrollView];

    self.stack = [[UIStackView alloc] init];
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    self.stack.axis = UILayoutConstraintAxisVertical;
    self.stack.spacing = kGap;
    self.stack.alignment = UIStackViewAlignmentFill;
    [self.scrollView addSubview:self.stack];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor      constraintEqualToAnchor:self.view.topAnchor],
        [self.scrollView.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor   constraintEqualToAnchor:self.view.bottomAnchor],
        [self.stack.topAnchor      constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor constant:8.0],
        [self.stack.leadingAnchor  constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor constant:kMargin],
        [self.stack.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor constant:-kMargin],
        [self.stack.bottomAnchor   constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor constant:-28.0],
        [self.stack.widthAnchor    constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor constant:-kMargin * 2],
    ]];

    [self.stack addArrangedSubview:[self buildBanner]];
    [self.stack addArrangedSubview:[self section:@"WHAT'S NEW" card:[self whatsNewCard]]];
    [self.stack addArrangedSubview:[self section:@"JAVASCRIPT TWEAKS" card:[self jsCard]]];
    [self.stack addArrangedSubview:[self section:@"REMOTECALL TWEAKS" card:[self rcCard]]];
    [self.stack addArrangedSubview:[self section:@"COMMUNITY" card:[self communityCard]]];
}

#pragma mark - Banner

- (UIView *)buildBanner
{
    UIView *banner = [[UIView alloc] init];
    banner.backgroundColor = [UIColor.systemCyanColor colorWithAlphaComponent:0.08];
    banner.layer.cornerRadius = 14.0;
    banner.layer.cornerCurve = kCACornerCurveContinuous;

    UIImageView *icon = [[UIImageView alloc] init];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    UIImage *appIcon = [UIImage imageNamed:@"AppIcon60x60"];
    if (!appIcon) {
        NSString *f = [[[NSBundle mainBundle] infoDictionary][@"CFBundleIcons"][@"CFBundlePrimaryIcon"][@"CFBundleIconFiles"] lastObject];
        appIcon = f ? [UIImage imageNamed:f] : nil;
    }
    icon.image = appIcon;
    icon.layer.cornerRadius = 12.0;
    icon.layer.cornerCurve = kCACornerCurveContinuous;
    icon.clipsToBounds = YES;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [banner addSubview:icon];

    UILabel *lbl = [[UILabel alloc] init];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    lbl.numberOfLines = 0;
    lbl.text = @"SpringBoard tweaks and JavaScript packages — no jailbreak required.";
    lbl.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
    lbl.textColor = UIColor.secondaryLabelColor;
    [banner addSubview:lbl];

    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor  constraintEqualToAnchor:banner.leadingAnchor constant:14.0],
        [icon.centerYAnchor  constraintEqualToAnchor:banner.centerYAnchor],
        [icon.widthAnchor    constraintEqualToConstant:44.0],
        [icon.heightAnchor   constraintEqualToConstant:44.0],
        [lbl.leadingAnchor   constraintEqualToAnchor:icon.trailingAnchor constant:12.0],
        [lbl.trailingAnchor  constraintEqualToAnchor:banner.trailingAnchor constant:-14.0],
        [lbl.topAnchor       constraintEqualToAnchor:banner.topAnchor constant:14.0],
        [lbl.bottomAnchor    constraintEqualToAnchor:banner.bottomAnchor constant:-14.0],
    ]];
    return banner;
}

#pragma mark - Section

- (UIView *)section:(NSString *)title card:(UIView *)card
{
    UIView *w = [[UIView alloc] init];
    UILabel *h = [[UILabel alloc] init];
    h.translatesAutoresizingMaskIntoConstraints = NO;
    h.attributedText = [[NSAttributedString alloc]
        initWithString:title attributes:@{
            NSFontAttributeName: [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold],
            NSForegroundColorAttributeName: UIColor.secondaryLabelColor,
            NSKernAttributeName: @(0.6),
        }];
    [w addSubview:h];

    card.translatesAutoresizingMaskIntoConstraints = NO;
    [w addSubview:card];

    [NSLayoutConstraint activateConstraints:@[
        [h.topAnchor     constraintEqualToAnchor:w.topAnchor],
        [h.leadingAnchor constraintEqualToAnchor:w.leadingAnchor constant:4.0],
        [card.topAnchor     constraintEqualToAnchor:h.bottomAnchor constant:8.0],
        [card.leadingAnchor constraintEqualToAnchor:w.leadingAnchor],
        [card.trailingAnchor constraintEqualToAnchor:w.trailingAnchor],
        [card.bottomAnchor  constraintEqualToAnchor:w.bottomAnchor],
    ]];
    return w;
}

#pragma mark - What's New

- (UIView *)whatsNewCard
{
    UIView *card = [self card];
    UIStackView *s = [self vstack:12.0];
    [card addSubview:s];
    [self pin:s in:card];

    [s addArrangedSubview:[self badgeRow:@"QuickLoader + RepoTweaks by @MinePlayer16 — JS tweak runners from local files and online sources"
                                   icon:@"bolt.fill" color:UIColor.systemOrangeColor]];
    [s addArrangedSubview:[self badgeRow:@"Default repo with Hide Dock by @MinePlayer16, Color Dock, FlexButBreaks, and more on the way"
                                   icon:@"arrow.down.circle.fill" color:UIColor.systemGreenColor]];
    [s addArrangedSubview:[self badgeRow:@"SnowBoard Lite, SBCustomizer, and SpringBoard stability fixes"
                                   icon:@"wrench.and.screwdriver.fill" color:UIColor.systemBlueColor]];
    return card;
}

#pragma mark - JS Tweaks

- (UIView *)jsCard
{
    UIView *card = [self card];
    UIStackView *s = [self vstack:12.0];
    [card addSubview:s];
    [self pin:s in:card];

    UILabel *intro = [self body:@"Run custom JS tweaks through Cyanide's SpringBoard bridge. Contributed by @MinePlayer16."];
    [s addArrangedSubview:intro];

    [s addArrangedSubview:[self badgeRow:@"Import .js files from Files with configurable @param settings"
                                   icon:@"doc.text.fill" color:UIColor.systemBlueColor]];
    [s addArrangedSubview:[self badgeRow:@"Add HTTPS repos in Sources, browse tweaks, install with one tap"
                                   icon:@"tray.and.arrow.down.fill" color:UIColor.systemGreenColor]];

    [s addArrangedSubview:[self sep]];

    UIStackView *btns = [self hstack:8.0];
    btns.distribution = UIStackViewDistributionFillEqually;
    [btns addArrangedSubview:[self actionBtn:@"QuickLoader" icon:@"doc.text.fill" color:UIColor.systemBlueColor sel:@selector(openQuickLoader)]];
    [btns addArrangedSubview:[self actionBtn:@"Add Source" icon:@"plus.circle.fill" color:UIColor.systemGreenColor sel:@selector(openSourcesTab)]];
    [btns.heightAnchor constraintEqualToConstant:42.0].active = YES;
    [s addArrangedSubview:btns];

    UILabel *note = [self footnote:@"Hide Dock by @MinePlayer16 available now. Color Dock, FlexButBreaks, Hide SearchPill, and more on the way."];
    [s addArrangedSubview:note];

    return card;
}

#pragma mark - RC Tweaks

- (UIView *)rcCard
{
    UIView *card = [self card];
    UIStackView *s = [self vstack:12.0];
    [card addSubview:s];
    [self pin:s in:card];

    [s addArrangedSubview:[self body:@"Native tweaks applied through a live SpringBoard channel — no system file changes."]];

    [s addArrangedSubview:[self featureRow:@"Status Bar" sub:@"StatBar, NSBar, NiceBar Lite"
                                     icon:@"chart.bar.fill" color:UIColor.systemTealColor]];
    [s addArrangedSubview:[self featureRow:@"Home Screen" sub:@"SBCustomizer, Layout Extras, Gravity Lite, SnowBoard Lite"
                                     icon:@"square.grid.3x3.fill" color:UIColor.systemBlueColor]];
    [s addArrangedSubview:[self featureRow:@"SpringBoard" sub:@"App Library, animations, Double-Tap Lock, App Switcher Grid"
                                     icon:@"sparkle" color:UIColor.systemCyanColor]];
    [s addArrangedSubview:[self featureRow:@"System" sub:@"OTA Updates, Watch Pairing, Call Recording, Location Sim"
                                     icon:@"gear" color:UIColor.systemGrayColor]];

    [s addArrangedSubview:[self footnote:@"Session-based — active while Cyanide runs, reset on respring. Don't force-quit from the App Switcher."]];

    return card;
}

#pragma mark - Community

- (UIView *)communityCard
{
    UIView *card = [self card];
    UIStackView *s = [self vstack:0.0];
    [card addSubview:s];
    [self pin:s in:card pad:0.0];

    [s addArrangedSubview:[self linkRow:@"Join Signal Group" icon:@"bubble.left.and.bubble.right.fill"
                                 color:UIColor.systemBlueColor url:kSignalGroupURL showSep:YES]];
    [s addArrangedSubview:[self linkRow:@"Report a Bug" icon:@"exclamationmark.bubble.fill"
                                 color:UIColor.systemRedColor url:kGitHubIssuesURL showSep:YES]];
    [s addArrangedSubview:[self linkRow:@"GitHub Repository" icon:@"chevron.left.forwardslash.chevron.right"
                                 color:UIColor.systemGrayColor url:kGitHubRepoURL showSep:YES]];
    [s addArrangedSubview:[self linkRow:@"Support on Patreon" icon:@"heart.fill"
                                 color:UIColor.systemPinkColor url:kPatreonURL showSep:NO]];
    return card;
}

#pragma mark - Primitives

- (UIView *)card
{
    UIView *v = [[UIView alloc] init];
    v.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    v.layer.cornerRadius = 14.0;
    v.layer.cornerCurve = kCACornerCurveContinuous;
    v.layer.shadowColor = UIColor.blackColor.CGColor;
    v.layer.shadowOpacity = 0.04f;
    v.layer.shadowRadius = 8.0;
    v.layer.shadowOffset = CGSizeMake(0, 2);
    return v;
}

- (UIStackView *)vstack:(CGFloat)spacing
{
    UIStackView *s = [[UIStackView alloc] init];
    s.translatesAutoresizingMaskIntoConstraints = NO;
    s.axis = UILayoutConstraintAxisVertical;
    s.spacing = spacing;
    s.alignment = UIStackViewAlignmentFill;
    return s;
}

- (UIStackView *)hstack:(CGFloat)spacing
{
    UIStackView *s = [[UIStackView alloc] init];
    s.axis = UILayoutConstraintAxisHorizontal;
    s.spacing = spacing;
    s.alignment = UIStackViewAlignmentFill;
    return s;
}

- (void)pin:(UIStackView *)s in:(UIView *)c
{
    [self pin:s in:c pad:kPad];
}

- (void)pin:(UIStackView *)s in:(UIView *)c pad:(CGFloat)p
{
    [NSLayoutConstraint activateConstraints:@[
        [s.topAnchor constraintEqualToAnchor:c.topAnchor constant:p],
        [s.leadingAnchor constraintEqualToAnchor:c.leadingAnchor constant:p],
        [s.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-p],
        [s.bottomAnchor constraintEqualToAnchor:c.bottomAnchor constant:-p],
    ]];
}

- (UIView *)iconBadge:(NSString *)iconName color:(UIColor *)color
{
    UIView *circle = [[UIView alloc] init];
    circle.translatesAutoresizingMaskIntoConstraints = NO;
    circle.backgroundColor = [color colorWithAlphaComponent:0.14];
    circle.layer.cornerRadius = 14.0;

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:13.0 weight:UIImageSymbolWeightSemibold];
    UIImageView *iv = [[UIImageView alloc] initWithImage:
        [[UIImage systemImageNamed:iconName withConfiguration:cfg]
            imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal]];
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    iv.contentMode = UIViewContentModeCenter;
    [circle addSubview:iv];

    [NSLayoutConstraint activateConstraints:@[
        [circle.widthAnchor constraintEqualToConstant:28.0],
        [circle.heightAnchor constraintEqualToConstant:28.0],
        [iv.centerXAnchor constraintEqualToAnchor:circle.centerXAnchor],
        [iv.centerYAnchor constraintEqualToAnchor:circle.centerYAnchor],
    ]];
    return circle;
}

- (UIView *)badgeRow:(NSString *)text icon:(NSString *)iconName color:(UIColor *)color
{
    UIStackView *row = [self hstack:10.0];
    row.alignment = UIStackViewAlignmentTop;

    UIView *badge = [self iconBadge:iconName color:color];
    [row addArrangedSubview:badge];

    UILabel *lbl = [[UILabel alloc] init];
    lbl.numberOfLines = 0;
    lbl.text = text;
    lbl.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
    lbl.textColor = UIColor.labelColor;
    [row addArrangedSubview:lbl];

    return row;
}

- (UIView *)featureRow:(NSString *)title sub:(NSString *)sub icon:(NSString *)iconName color:(UIColor *)color
{
    UIStackView *row = [self hstack:10.0];
    row.alignment = UIStackViewAlignmentTop;

    UIView *badge = [self iconBadge:iconName color:color];
    [row addArrangedSubview:badge];

    UIStackView *text = [self vstack:1.0];
    UILabel *t = [[UILabel alloc] init];
    t.text = title;
    t.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
    t.textColor = UIColor.labelColor;
    [text addArrangedSubview:t];
    UILabel *s = [[UILabel alloc] init];
    s.text = sub;
    s.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightRegular];
    s.textColor = UIColor.secondaryLabelColor;
    s.numberOfLines = 0;
    [text addArrangedSubview:s];
    [row addArrangedSubview:text];

    return row;
}

- (UIView *)linkRow:(NSString *)title icon:(NSString *)iconName color:(UIColor *)color url:(NSString *)url showSep:(BOOL)showSep
{
    UIView *container = [[UIView alloc] init];

    UIView *badge = [self iconBadge:iconName color:color];
    [container addSubview:badge];

    UILabel *lbl = [[UILabel alloc] init];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    lbl.text = title;
    lbl.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightRegular];
    lbl.textColor = UIColor.labelColor;
    [container addSubview:lbl];

    UIImageSymbolConfiguration *chevCfg = [UIImageSymbolConfiguration configurationWithPointSize:12.0 weight:UIImageSymbolWeightSemibold];
    UIImageView *chev = [[UIImageView alloc] initWithImage:
        [[UIImage systemImageNamed:@"chevron.right" withConfiguration:chevCfg]
            imageWithTintColor:UIColor.tertiaryLabelColor renderingMode:UIImageRenderingModeAlwaysOriginal]];
    chev.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:chev];

    [NSLayoutConstraint activateConstraints:@[
        [badge.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:14.0],
        [badge.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [lbl.leadingAnchor constraintEqualToAnchor:badge.trailingAnchor constant:12.0],
        [lbl.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [chev.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-14.0],
        [chev.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [container.heightAnchor constraintEqualToConstant:48.0],
    ]];

    if (showSep) {
        UIView *line = [[UIView alloc] init];
        line.translatesAutoresizingMaskIntoConstraints = NO;
        line.backgroundColor = UIColor.separatorColor;
        [container addSubview:line];
        [NSLayoutConstraint activateConstraints:@[
            [line.leadingAnchor constraintEqualToAnchor:lbl.leadingAnchor],
            [line.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
            [line.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
            [line.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
        ]];
    }

    UIButton *tap = [UIButton buttonWithType:UIButtonTypeCustom];
    tap.translatesAutoresizingMaskIntoConstraints = NO;
    __weak typeof(self) ws = self;
    [tap addAction:[UIAction actionWithHandler:^(UIAction *_) { [ws openURLString:url]; }] forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:tap];
    [NSLayoutConstraint activateConstraints:@[
        [tap.topAnchor constraintEqualToAnchor:container.topAnchor],
        [tap.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [tap.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [tap.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];

    return container;
}

- (UIView *)sep
{
    UIView *v = [[UIView alloc] init];
    v.backgroundColor = [UIColor.separatorColor colorWithAlphaComponent:0.3];
    [v.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale].active = YES;
    return v;
}

- (UILabel *)body:(NSString *)text
{
    UILabel *l = [[UILabel alloc] init];
    l.text = text;
    l.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
    l.textColor = UIColor.secondaryLabelColor;
    l.numberOfLines = 0;
    return l;
}

- (UILabel *)footnote:(NSString *)text
{
    UILabel *l = [[UILabel alloc] init];
    l.text = text;
    l.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular];
    l.textColor = UIColor.tertiaryLabelColor;
    l.numberOfLines = 0;
    return l;
}

- (UIButton *)actionBtn:(NSString *)title icon:(NSString *)iconName color:(UIColor *)color sel:(SEL)sel
{
    UIButtonConfiguration *cfg = [UIButtonConfiguration filledButtonConfiguration];
    cfg.title = title;
    cfg.image = [UIImage systemImageNamed:iconName];
    cfg.imagePadding = 6.0;
    cfg.imagePlacement = NSDirectionalRectEdgeLeading;
    cfg.cornerStyle = UIButtonConfigurationCornerStyleLarge;
    cfg.baseBackgroundColor = [color colorWithAlphaComponent:0.12];
    cfg.baseForegroundColor = color;
    cfg.preferredSymbolConfigurationForImage = [UIImageSymbolConfiguration configurationWithPointSize:13.0 weight:UIImageSymbolWeightSemibold];

    return [UIButton buttonWithConfiguration:cfg primaryAction:[UIAction actionWithHandler:^(UIAction *_) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [self performSelector:sel];
        #pragma clang diagnostic pop
    }]];
}

#pragma mark - Navigation

- (void)openURLString:(NSString *)url
{
    NSURL *u = [NSURL URLWithString:url];
    if (u) [[UIApplication sharedApplication] openURL:u options:@{} completionHandler:nil];
}

- (void)openQuickLoader
{
    UITabBarController *tab = self.tabBarController;
    if (!tab) return;
    for (NSUInteger i = 0; i < tab.viewControllers.count; i++) {
        UIViewController *vc = tab.viewControllers[i];
        if ([vc.tabBarItem.title isEqualToString:@"Settings"]) {
            UINavigationController *nav = [vc isKindOfClass:UINavigationController.class] ? (UINavigationController *)vc : nil;
            if (!nav) return;
            [nav popToRootViewControllerAnimated:NO];
            [nav pushViewController:[[SettingsViewController alloc] initWithUnderlyingSection:25 bundleTitle:@"QuickLoader"] animated:NO];
            tab.selectedIndex = i;
            return;
        }
    }
}

- (void)openSourcesTab
{
    UITabBarController *tab = self.tabBarController;
    if (!tab) return;
    for (NSUInteger i = 0; i < tab.viewControllers.count; i++) {
        if ([tab.viewControllers[i].tabBarItem.title isEqualToString:@"Sources"]) {
            tab.selectedIndex = i;
            return;
        }
    }
}

@end
