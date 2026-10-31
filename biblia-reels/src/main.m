#import "BRUI.h"
#import <AVFoundation/AVFoundation.h>

@implementation BRRootController
- (void)viewDidLoad {
    [super viewDidLoad];
    BRFeedController *feed = [BRFeedController new];
    UINavigationController *discover = [[UINavigationController alloc] initWithRootViewController:[BRDiscoverController new]];
    UIViewController *create = [UIViewController new];
    UINavigationController *messages = [[UINavigationController alloc] initWithRootViewController:[BRMessagesController new]];
    UINavigationController *profile = [[UINavigationController alloc] initWithRootViewController:[BRProfileController new]];
    BRApplyNavStyle(discover);
    BRApplyNavStyle(messages);
    BRApplyNavStyle(profile);
    feed.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Acasă" image:[UIImage systemImageNamed:@"house.fill"] tag:0];
    discover.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Descoperă" image:[UIImage systemImageNamed:@"magnifyingglass"] tag:1];
    create.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Creează" image:[UIImage systemImageNamed:@"plus.circle.fill"] tag:2];
    messages.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Mesaje" image:[UIImage systemImageNamed:@"message.fill"] tag:3];
    profile.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Profil" image:[UIImage systemImageNamed:@"person.fill"] tag:4];
    self.viewControllers = @[feed, discover, create, messages, profile];
    self.delegate = (id<UITabBarControllerDelegate>)self;
    UITabBarAppearance *look = [UITabBarAppearance new];
    [look configureWithOpaqueBackground];
    look.backgroundColor = [UIColor colorWithWhite:0 alpha:0.94];
    look.stackedLayoutAppearance.normal.iconColor = [UIColor colorWithWhite:1 alpha:0.55];
    look.stackedLayoutAppearance.normal.titleTextAttributes = @{NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.55]};
    look.stackedLayoutAppearance.selected.iconColor = BRGold();
    look.stackedLayoutAppearance.selected.titleTextAttributes = @{NSForegroundColorAttributeName: BRGold()};
    self.tabBar.standardAppearance = look;
    self.tabBar.scrollEdgeAppearance = look;
    self.tabBar.tintColor = BRGold();
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(openItem:) name:BROpenItem object:nil];
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }
- (BOOL)tabBarController:(UITabBarController *)tabBarController shouldSelectViewController:(UIViewController *)viewController {
    if (viewController == self.viewControllers[2]) {
        BRCreateController *create = [BRCreateController new];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:create];
        nav.modalPresentationStyle = UIModalPresentationFullScreen;
        BRApplyNavStyle(nav);
        [self presentViewController:nav animated:YES completion:nil];
        return NO;
    }
    return YES;
}
- (void)openItem:(NSNotification *)note {
    self.selectedIndex = 0;
    NSString *itemId = note.userInfo[@"id"];
    if (![itemId isKindOfClass:[NSString class]] || itemId.length == 0) return;
    BRFeedController *feed = (BRFeedController *)self.viewControllers[0];
    [feed openItemId:itemId];
}
@end

@implementation BRAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    NSError *error = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayback error:&error];
    [session setActive:YES error:&error];
    [[BRStore shared] load];
    [[BRCatalog shared] loadBundled];
    [[BRCatalog shared] refreshFromNetwork];
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.backgroundColor = UIColor.blackColor;
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.window.rootViewController = [BRRootController new];
    [self.window makeKeyAndVisible];
    return YES;
}
- (void)applicationDidEnterBackground:(UIApplication *)application {
    [[NSNotificationCenter defaultCenter] postNotificationName:BRPauseMedia object:nil];
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([BRAppDelegate class]));
    }
}
