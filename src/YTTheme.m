#import "YTTheme.h"
@implementation YTTheme
+ (UIColor *)bg    { return [UIColor colorWithRed:0.06 green:0.06 blue:0.06 alpha:1]; } // #0F0F0F
+ (UIColor *)bar   { return [UIColor colorWithWhite:0.0 alpha:1]; }
+ (UIColor *)ink   { return [UIColor whiteColor]; }
+ (UIColor *)muted { return [UIColor colorWithWhite:0.67 alpha:1]; }  // #AAAAAA
+ (UIColor *)line  { return [UIColor colorWithWhite:0.15 alpha:1]; }
+ (UIColor *)red   { return [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:1]; }
+ (UIColor *)card  { return [UIColor colorWithWhite:0.13 alpha:1]; }  // #212121
// Eigenes Zeichen: roter Kreis mit weißem Play (kein YouTube-Logo – Markenrecht). Quadratisch w×w.
+ (UIImage *)logo:(CGFloat)w {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(w,w),NO,0);
    [[UIColor colorWithRed:1.0 green:0.176 blue:0.239 alpha:1] setFill]; [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0,0,w,w)] fill];
    UIBezierPath *tri=[UIBezierPath bezierPath];
    [tri moveToPoint:CGPointMake(w*0.40,w*0.29)]; [tri addLineToPoint:CGPointMake(w*0.40,w*0.71)]; [tri addLineToPoint:CGPointMake(w*0.74,w*0.5)]; [tri closePath];
    [[UIColor whiteColor] setFill]; [tri fill];
    UIImage *img=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return img;
}
@end
