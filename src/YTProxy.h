#import <Foundation/Foundation.h>
// Lokaler HTTP->HTTPS-Relay. Grund: iOS-6-MPMoviePlayer lehnt googlevideos modernes Zertifikat ab
// (alter Root-Store). Der Proxy holt den Stream über mbedTLS (ohne Cert-Prüfung) und reicht ihn
// unverschlüsselt an 127.0.0.1 durch. Range-Requests (Scrubben/Seek) werden transparent durchgereicht.
@interface YTProxy : NSObject
+ (void)start;                                         // idempotent
+ (NSString *)localURLFor:(NSString *)remoteHTTPSURL;  // -> http://127.0.0.1:<port>/?u=<base64url>
@end
