#import "YTTheme.h"
@implementation YTTheme
+ (UIColor *)bg    { return [UIColor colorWithRed:0.06 green:0.06 blue:0.06 alpha:1]; } // #0F0F0F
+ (UIColor *)bar   { return [UIColor colorWithWhite:0.0 alpha:1]; }
+ (UIColor *)ink   { return [UIColor whiteColor]; }
+ (UIColor *)muted { return [UIColor colorWithWhite:0.67 alpha:1]; }  // #AAAAAA
+ (UIColor *)line  { return [UIColor colorWithWhite:0.15 alpha:1]; }
+ (UIColor *)red   { return [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:1]; }
+ (UIColor *)card  { return [UIColor colorWithWhite:0.13 alpha:1]; }  // #212121
+ (UIImage *)logo:(CGFloat)w {
    CGFloat h=w*0.70;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(w,h),NO,0);
    UIBezierPath *rr=[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0,0,w,h) cornerRadius:h*0.28];
    [[self red] setFill]; [rr fill];
    UIBezierPath *tri=[UIBezierPath bezierPath];
    [tri moveToPoint:CGPointMake(w*0.40,h*0.30)]; [tri addLineToPoint:CGPointMake(w*0.40,h*0.70)]; [tri addLineToPoint:CGPointMake(w*0.66,h*0.50)]; [tri closePath];
    [[UIColor whiteColor] setFill]; [tri fill];
    UIImage *img=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return img;
}
@end
