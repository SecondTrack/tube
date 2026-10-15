#import <UIKit/UIKit.h>
#import <signal.h>
int main(int argc, char *argv[]) {
    signal(SIGPIPE, SIG_IGN);   // abgebrochene Verbindung (Player/Server weg) -> write() liefert EPIPE statt App-Absturz
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, @"YTAppDelegate"); }
}
