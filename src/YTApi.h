#import <Foundation/Foundation.h>
// YouTube ohne Server & ohne PoToken: Suche über den WEB-Client, Streams über den ANDROID_VR-Client
// (liefert aktuell DIREKTE itag-18-URLs, kein Signatur-Decipher nötig). Alles über YTNet (mbedTLS).
@interface YTApi : NSObject
// results: @[ {id,title,author,length,thumb} ]
+ (void)search:(NSString *)query completion:(void(^)(NSArray *results))done;
// Liefert direkt abspielbare URLs. videoURL = itag18 (360p H.264+AAC, muxed). audioURL = bestes AAC.
+ (void)streams:(NSString *)videoId
     completion:(void(^)(NSString *videoURL, NSString *audioURL, NSString *title, NSString *author, NSString *err))done;
// Kommentare: @[ {author,text,likes,avatar} ]
+ (void)comments:(NSString *)videoId completion:(void(^)(NSArray *comments))done;
@end
