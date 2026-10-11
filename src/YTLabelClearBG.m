// iOS-6-Fix: jedes UILabel bekommt hier per Default einen weißen (opaken) Hintergrund
// -> weißer Text wird zu weißen Kästen. Diese Kategorie swizzelt initWithFrame:, sodass
// jedes Label automatisch transparent ist. +load läuft beim App-Start.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@implementation UILabel (YTClearBG)

- (instancetype)yt_initWithFrame:(CGRect)frame {
    UILabel *l = [self yt_initWithFrame:frame];
    if (l) l.backgroundColor = [UIColor clearColor];
    return l;
}

+ (void)load {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Method orig = class_getInstanceMethod(self, @selector(initWithFrame:));
        Method repl = class_getInstanceMethod(self, @selector(yt_initWithFrame:));
        if (orig && repl) method_exchangeImplementations(orig, repl);
    });
}

@end
