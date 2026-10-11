#import <UIKit/UIKit.h>
// YouTube-Look: hell & klar, roter Akzent.
@interface YTTheme : NSObject
+ (UIColor *)bg;      // weiß
+ (UIColor *)bar;     // sehr helles Grau (Kopf/Leisten)
+ (UIColor *)ink;     // fast-schwarz
+ (UIColor *)muted;   // grau
+ (UIColor *)line;    // hairline
+ (UIColor *)red;     // #FF0000
+ (UIColor *)card;    // #212121
// YouTube-Logo: rotes abgerundetes Rechteck + weißes Play, Breite w.
+ (UIImage *)logo:(CGFloat)w;
@end
