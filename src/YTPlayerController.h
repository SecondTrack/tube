#import <UIKit/UIKit.h>
@interface YTPlayerController : UIViewController
+ (void)closeMini;   // laufenden Mini-Player schließen
- (id)initWithVideoId:(NSString *)videoId title:(NSString *)title author:(NSString *)author avatar:(NSString *)avatar;
@end
