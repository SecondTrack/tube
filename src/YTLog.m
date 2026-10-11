#import "YTLog.h"

static NSMutableString *gLog=nil;
void YTLog(NSString *fmt, ...) {
    @synchronized([NSObject class]) {
        if(!gLog) gLog=[NSMutableString string];
        va_list a; va_start(a,fmt); NSString *s=[[NSString alloc] initWithFormat:fmt arguments:a]; va_end(a);
        NSDate *d=[NSDate date];
        [gLog appendFormat:@"%.1f  %@\n", [d timeIntervalSince1970], s];
        if(gLog.length>60000) [gLog deleteCharactersInRange:NSMakeRange(0,20000)];
        [gLog writeToFile:@"/var/mobile/.tube-log" atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    }
}
