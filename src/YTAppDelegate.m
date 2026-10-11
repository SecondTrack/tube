#import <UIKit/UIKit.h>
#import "YTSearchController.h"
#import "YTTheme.h"
#import "YTProxy.h"

// Nav-Controller, der Orientierung an den sichtbaren Screen weiterreicht (iOS6 tut das nicht von selbst).
@interface YTNav : UINavigationController @end
@implementation YTNav
- (NSUInteger)supportedInterfaceOrientations { UIViewController *t=self.topViewController; return t?[t supportedInterfaceOrientations]:UIInterfaceOrientationMaskPortrait; }
- (BOOL)shouldAutorotate { UIViewController *t=self.topViewController; return t?[t shouldAutorotate]:NO; }
@end

@interface YTAppDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation YTAppDelegate { UIWindow *_w; }
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)o {
    [YTProxy start];   // lokaler TLS-Relay für den Player
    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleLightContent];
    _w=[[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    YTSearchController *s=[[YTSearchController alloc] init];
    YTNav *nav=[[YTNav alloc] initWithRootViewController:s];
    [nav setNavigationBarHidden:YES animated:NO];   // eigene dunkle Kopfzeilen
    _w.rootViewController=nav; [_w makeKeyAndVisible];
    return YES;
}
- (NSUInteger)application:(UIApplication *)application supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    return UIInterfaceOrientationMaskPortrait;   // App bleibt Hochformat; Vollbild-Video drehen wir selbst
}
@end
