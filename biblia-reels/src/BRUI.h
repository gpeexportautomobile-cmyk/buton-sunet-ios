#import <UIKit/UIKit.h>
#import "BRData.h"

void BRApplyNavStyle(UINavigationController *nav);
void BROpenItemFrom(UIViewController *from, NSString *itemId);

@interface BRFeedController : UIViewController
- (void)openItemId:(NSString *)itemId;
- (void)pausePlayback;
@end

@interface BRDiscoverController : UIViewController
@end

@interface BRCreateController : UIViewController
@end

@interface BRMessagesController : UIViewController
@end

@interface BRChatController : UIViewController
@property (nonatomic, copy) NSString *characterId;
@end

@interface BRProfileController : UIViewController
@end

@interface BRCharacterController : UIViewController
@property (nonatomic, copy) NSString *characterId;
@end

@interface BRCommentsController : UIViewController
@property (nonatomic, copy) NSString *itemId;
@property (nonatomic, copy) NSString *titleText;
@end

@interface BRRootController : UITabBarController
@end

@interface BRAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
