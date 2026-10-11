#import "YTApi.h"
#import "YTNet.h"
#import "YTLog.h"
#import "MeshL10n.h"

#define YT_KEY @"AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8"
// WICHTIG: clientVersion muss AKTUELL sein, sonst FAILED_PRECONDITION. ANDROID 20.03.x gibt
// direkte itag-18-URLs ohne PoToken. (Bei Ablauf ggf. clientVersion hochziehen.)
#define AND_UA @"com.google.android.youtube/20.03.36 (Linux; U; Android 14) gzip"
#define VR_UA  @"com.google.android.apps.youtube.vr.oculus/1.60.19 (Linux; U; Android 12; Quest 3)"

@implementation YTApi

// POST youtubei/v1/<ep> mit Client-Context; gibt geparstes JSON (dict) oder nil.
+ (NSDictionary *)post:(NSString *)endpoint client:(NSDictionary *)client ua:(NSString *)ua extra:(NSDictionary *)extra {
    NSMutableDictionary *body=[NSMutableDictionary dictionary];
    body[@"context"]=@{@"client":client};
    [body addEntriesFromDictionary:extra];
    NSData *jb=[NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
    NSArray *hdr=@[[@"User-Agent: " stringByAppendingString:ua], @"Content-Type: application/json"];
    int st=0;
    NSData *d=[YTNet request:@"POST" host:@"www.youtube.com"
                       path:[@"/youtubei/v1/" stringByAppendingFormat:@"%@?key=%@",endpoint,YT_KEY]
                    headers:hdr body:jb status:&st];
    YTLog(@"api %@ -> HTTP %d, %lu B", endpoint, st, (unsigned long)d.length);
    if(!d.length) return nil;
    id j=[NSJSONSerialization JSONObjectWithData:d options:0 error:NULL];
    return [j isKindOfClass:[NSDictionary class]]?j:nil;
}

// Rekursiv alle Dicts einsammeln, die unter dem Schlüssel `key` ein Dict tragen.
static void collect(id node, NSString *key, NSMutableArray *out) {
    if([node isKindOfClass:[NSDictionary class]]){
        id hit=node[key];
        if([hit isKindOfClass:[NSDictionary class]]) [out addObject:hit];
        for(id k in [node allKeys]) collect(node[k], key, out);
    } else if([node isKindOfClass:[NSArray class]]){
        for(id e in node) collect(e, key, out);
    }
}
static NSString *runsText(id o){
    if([o isKindOfClass:[NSDictionary class]]){
        if([o[@"simpleText"] isKindOfClass:[NSString class]]) return o[@"simpleText"];
        id runs=o[@"runs"];
        if([runs isKindOfClass:[NSArray class]]){
            // ALLE runs verketten — YouTube zerlegt Titel mit Emojis in mehrere runs
            // (Text / Emoji / Text); nur runs[0] zu nehmen schnitt den Titel am ersten Emoji ab.
            NSMutableString *s=[NSMutableString string];
            for(id r in runs){
                if(![r isKindOfClass:[NSDictionary class]]) continue;
                if([r[@"text"] isKindOfClass:[NSString class]]) [s appendString:r[@"text"]];
                // Emoji-Run ohne text: echtes Unicode-Emoji aus emoji.emojiId holen (Fallback)
                else { id em=r[@"emoji"]; if([em isKindOfClass:[NSDictionary class]]&&[em[@"emojiId"] isKindOfClass:[NSString class]]) [s appendString:em[@"emojiId"]]; }
            }
            return s;
        }
    }
    return @"";
}
static NSString *thumbURL(id vr){
    id t=vr[@"thumbnail"]; if(![t isKindOfClass:[NSDictionary class]]) return @"";
    id arr=t[@"thumbnails"]; if(![arr isKindOfClass:[NSArray class]]||![arr count]) return @"";
    id im=[arr lastObject]; // größtes (große Karte)
    return ([im isKindOfClass:[NSDictionary class]]&&[im[@"url"] isKindOfClass:[NSString class]])?im[@"url"]:@"";
}
static NSString *avatarURL(id vr){
    id a=vr[@"channelThumbnailSupportedRenderers"];
    if([a isKindOfClass:[NSDictionary class]]){ id b=a[@"channelThumbnailWithLinkRenderer"];
        if([b isKindOfClass:[NSDictionary class]]){ id t=b[@"thumbnail"];
            if([t isKindOfClass:[NSDictionary class]]){ id arr=t[@"thumbnails"];
                if([arr isKindOfClass:[NSArray class]]&&[arr count]){ id im=arr[0];
                    if([im isKindOfClass:[NSDictionary class]]&&[im[@"url"] isKindOfClass:[NSString class]]) return im[@"url"]; } } } }
    return @"";
}

+ (void)search:(NSString *)query completion:(void(^)(NSArray *))done {
    dispatch_async(dispatch_get_global_queue(0,0), ^{
        NSDictionary *web=@{@"clientName":@"WEB",@"clientVersion":@"2.20240606.06.00",@"hl":@"en",@"gl":@"US"};
        NSDictionary *j=[self post:@"search" client:web ua:@"Mozilla/5.0" extra:@{@"query":query?:@""}];
        NSMutableArray *vrs=[NSMutableArray array]; collect(j, @"videoRenderer", vrs);
        NSMutableArray *out=[NSMutableArray array]; NSMutableSet *seen=[NSMutableSet set];
        for(NSDictionary *vr in vrs){
            NSString *vid=[vr[@"videoId"] isKindOfClass:[NSString class]]?vr[@"videoId"]:nil;
            if(!vid || [seen containsObject:vid]) continue; [seen addObject:vid];
            [out addObject:@{@"id":vid,
                             @"title":runsText(vr[@"title"]),
                             @"author":runsText(vr[@"ownerText"]),
                             @"length":runsText(vr[@"lengthText"]),
                             @"views":runsText(vr[@"viewCountText"]),
                             @"published":runsText(vr[@"publishedTimeText"]),
                             @"thumb":thumbURL(vr),
                             @"avatar":avatarURL(vr)}];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ if(done)done(out); });
    });
}

+ (void)streams:(NSString *)videoId
     completion:(void(^)(NSString *, NSString *, NSString *, NSString *, NSString *))done {
    dispatch_async(dispatch_get_global_queue(0,0), ^{
        // Mehrere Clients mit AKTUELLER Version, bis einer direkte URLs liefert (kein PoToken).
        NSArray *clients=@[
          @{@"ua":AND_UA, @"c":@{@"clientName":@"ANDROID",@"clientVersion":@"20.03.36",@"androidSdkVersion":@34,@"osName":@"Android",@"osVersion":@"14",@"hl":@"en",@"gl":@"US"}},
          @{@"ua":VR_UA,  @"c":@{@"clientName":@"ANDROID_VR",@"clientVersion":@"1.60.19",@"deviceModel":@"Quest 3",@"osName":@"Android",@"osVersion":@"12",@"androidSdkVersion":@32,@"hl":@"en",@"gl":@"US"}},
        ];
        NSString *err=nil, *videoURL=nil, *audioURL=nil, *title=@"", *author=@"", *status=nil;
        for(NSDictionary *cl in clients){
            NSDictionary *j=[self post:@"player" client:cl[@"c"] ua:cl[@"ua"]
                                extra:@{@"videoId":videoId?:@"",@"contentCheckOk":@YES,@"racyCheckOk":@YES}];
            id ps=j[@"playabilityStatus"]; status=[ps isKindOfClass:[NSDictionary class]]?ps[@"status"]:nil;
            id vd=j[@"videoDetails"];
            if([vd isKindOfClass:[NSDictionary class]]){ if([vd[@"title"] isKindOfClass:[NSString class]])title=vd[@"title"]; if([vd[@"author"] isKindOfClass:[NSString class]])author=vd[@"author"]; }
            id sd=j[@"streamingData"];
            if([sd isKindOfClass:[NSDictionary class]]){
                NSMutableArray *all=[NSMutableArray array];
                if([sd[@"formats"] isKindOfClass:[NSArray class]]) [all addObjectsFromArray:sd[@"formats"]];
                if([sd[@"adaptiveFormats"] isKindOfClass:[NSArray class]]) [all addObjectsFromArray:sd[@"adaptiveFormats"]];
                int bestAudioBr=-1;
                for(NSDictionary *f in all){
                    if(![f isKindOfClass:[NSDictionary class]]) continue;
                    NSString *url=[f[@"url"] isKindOfClass:[NSString class]]?f[@"url"]:nil; if(!url) continue;  // nur direkte URLs
                    NSString *mime=[f[@"mimeType"] isKindOfClass:[NSString class]]?f[@"mimeType"]:@"";
                    NSInteger itag=[f[@"itag"] respondsToSelector:@selector(integerValue)]?[f[@"itag"] integerValue]:0;
                    if(itag==18) videoURL=url;   // 360p muxed H.264+AAC -> iPod-nativ
                    if([mime rangeOfString:@"audio/mp4"].location!=NSNotFound){
                        int br=[f[@"bitrate"] respondsToSelector:@selector(intValue)]?[f[@"bitrate"] intValue]:0;
                        if(br>bestAudioBr){ bestAudioBr=br; audioURL=url; }
                    }
                }
                if(!videoURL) for(NSDictionary *f in all){ if(![f isKindOfClass:[NSDictionary class]])continue; NSString*url=f[@"url"]; NSString*mime=f[@"mimeType"]; if([url isKindOfClass:[NSString class]]&&[mime isKindOfClass:[NSString class]]&&[mime rangeOfString:@"video/mp4"].location!=NSNotFound&&f[@"audioChannels"]){ videoURL=url; break; } }
            }
            YTLog(@"streams %@ [%@]: status=%@ video=%@ audio=%@", videoId, cl[@"c"][@"clientName"], status?:@"-", videoURL?@"yes":@"no", audioURL?@"yes":@"no");
            if(videoURL || audioURL) break;   // Treffer -> fertig
        }
        if(!videoURL && !audioURL){
            if([status isEqualToString:@"LOGIN_REQUIRED"] || [status isEqualToString:@"UNPLAYABLE"] || [status isEqualToString:@"ERROR"])
                err=L(@"This video is blocked (age/region/rights). Most others work.");
            else err=status?LF(@"Not playable (%@)",status):L(@"No streams found.");
        }
        dispatch_async(dispatch_get_main_queue(), ^{ if(done)done(videoURL,audioURL,title,author,err); });
    });
}

+ (void)comments:(NSString *)videoId completion:(void(^)(NSArray *))done {
    dispatch_async(dispatch_get_global_queue(0,0), ^{
        NSDictionary *web=@{@"clientName":@"WEB",@"clientVersion":@"2.20250101.00.00",@"hl":@"en",@"gl":@"US"};
        NSMutableArray *out=[NSMutableArray array];
        NSDictionary *n1=[self post:@"next" client:web ua:@"Mozilla/5.0" extra:@{@"videoId":videoId?:@""}];
        // Kommentar-Continuation-Token suchen
        NSMutableArray *conts=[NSMutableArray array]; collect(n1, @"continuationItemRenderer", conts);
        NSString *tok=nil;
        for(NSDictionary *c in conts){ id ce=c[@"continuationEndpoint"]; if([ce isKindOfClass:[NSDictionary class]]){ id cc=ce[@"continuationCommand"]; if([cc isKindOfClass:[NSDictionary class]] && [cc[@"token"] isKindOfClass:[NSString class]]){ tok=cc[@"token"]; break; } } }
        if(tok.length){
            NSDictionary *n2=[self post:@"next" client:web ua:@"Mozilla/5.0" extra:@{@"continuation":tok}];
            NSMutableArray *ents=[NSMutableArray array]; collect(n2, @"commentEntityPayload", ents);
            for(NSDictionary *e in ents){
                id au=e[@"author"]; id pr=e[@"properties"]; id tb=e[@"toolbar"];
                NSString *name=([au isKindOfClass:[NSDictionary class]]&&[au[@"displayName"] isKindOfClass:[NSString class]])?au[@"displayName"]:@"";
                NSString *avatar=([au isKindOfClass:[NSDictionary class]]&&[au[@"avatarThumbnailUrl"] isKindOfClass:[NSString class]])?au[@"avatarThumbnailUrl"]:@"";
                NSString *text=@""; if([pr isKindOfClass:[NSDictionary class]]){ id ct=pr[@"content"]; if([ct isKindOfClass:[NSDictionary class]]&&[ct[@"content"] isKindOfClass:[NSString class]]) text=ct[@"content"]; }
                NSString *likes=([tb isKindOfClass:[NSDictionary class]]&&[tb[@"likeCountNotliked"] isKindOfClass:[NSString class]])?tb[@"likeCountNotliked"]:@"";
                if(name.length||text.length) [out addObject:@{@"author":name,@"text":text,@"likes":likes,@"avatar":avatar}];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ if(done)done(out); });
    });
}
@end
