#import <Foundation/Foundation.h>

@interface YTNet : NSObject
// Low-Level HTTPS (eigenes TLS 1.2 via mbedTLS). headers = Array von "Key: Value". body optional.
+ (NSData *)request:(NSString *)method host:(NSString *)host path:(NSString *)path
            headers:(NSArray *)headers body:(NSData *)body status:(int *)status;
// JSON-Komfort: baut Header (Bearer + Content-Type), serialisiert jsonBody, parst Antwort. Gibt dict/array oder nil.
+ (id)json:(NSString *)method host:(NSString *)host path:(NSString *)path
    bearer:(NSString *)token jsonBody:(id)jsonBody status:(int *)status;
// URL-Encode einer Pfad-/Query-Komponente (alle reservierten Zeichen).
+ (NSString *)enc:(NSString *)s;
@end
