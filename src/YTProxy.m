#import "YTProxy.h"
#import "YTLog.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <errno.h>
#import <sys/time.h>
#import "mbedtls/ssl.h"
#import "mbedtls/net_sockets.h"
#import "mbedtls/ctr_drbg.h"

#define PROXY_PORT 8791
#define PROXY_MAX_RELAYS 3   // A4/256 MB: höchstens 3 gleichzeitige Relays (je TLS-Kontext + Puffer)
#define PROXY_SLOT_WAIT_S 20  // so lange wartet eine neue Verbindung auf einen freien Platz, sonst 503

static int gListen=-1;

// ---- base64url (ohne Padding) ----
static NSString *b64urlEnc(NSString *s){
    static const char *t="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    NSData *d=[s dataUsingEncoding:NSUTF8StringEncoding]; const unsigned char *b=d.bytes; NSUInteger n=d.length;
    NSMutableString *o=[NSMutableString string];
    for(NSUInteger i=0;i<n;i+=3){ unsigned v=b[i]<<16; int k=1; if(i+1<n){v|=b[i+1]<<8;k=2;} if(i+2<n){v|=b[i+2];k=3;}
        [o appendFormat:@"%c%c",t[(v>>18)&63],t[(v>>12)&63]]; if(k>=2)[o appendFormat:@"%c",t[(v>>6)&63]]; if(k>=3)[o appendFormat:@"%c",t[v&63]]; }
    return o;
}
static NSString *b64urlDec(const char *s,int len){
    static signed char rev[256]; static int init=0;
    if(!init){ memset(rev,-1,256); const char *t="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"; for(int i=0;i<64;i++)rev[(unsigned char)t[i]]=i; init=1; }
    NSMutableData *d=[NSMutableData data]; int val=0,bits=0;
    for(int i=0;i<len;i++){ signed char c=rev[(unsigned char)s[i]]; if(c<0)continue; val=(val<<6)|c; bits+=6; if(bits>=8){ bits-=8; unsigned char ch=(val>>bits)&0xff; [d appendBytes:&ch length:1]; } }
    return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
}

static int mxEnt(void*d,unsigned char*o,size_t n){ (void)d; for(size_t i=0;i<n;i++)o[i]=arc4random()&0xff; return 0; }

// Liest Request-Header vom Client bis \r\n\r\n.
static NSString *readHeaders(int fd){
    NSMutableData *d=[NSMutableData data]; char c; int nl=0;
    while(read(fd,&c,1)==1){ [d appendBytes:&c length:1]; if(c=='\n'){ if(++nl>=2 && d.length>=4){ const char*p=d.bytes; if(p[d.length-4]=='\r'&&p[d.length-3]=='\n'&&p[d.length-2]=='\r'&&p[d.length-1]=='\n')break; } } else if(c!='\r') nl=0; if(d.length>8192)break; }
    return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
}

// Relay: holt remoteURL per TLS (ohne Cert-Prüfung) und schreibt die rohe HTTP-Antwort an clientfd.
static void relay(int clientfd, NSString *remoteURL, NSString *rangeHdr){
    NSString *r=remoteURL; if([r hasPrefix:@"https://"]) r=[r substringFromIndex:8];
    NSRange slash=[r rangeOfString:@"/"];
    NSString *host = slash.location==NSNotFound?r:[r substringToIndex:slash.location];
    NSString *path = slash.location==NSNotFound?@"/":[r substringFromIndex:slash.location];

    mbedtls_net_context srv; mbedtls_ssl_context ssl; mbedtls_ssl_config conf; mbedtls_ctr_drbg_context ctr;
    mbedtls_net_init(&srv); mbedtls_ssl_init(&ssl); mbedtls_ssl_config_init(&conf); mbedtls_ctr_drbg_init(&ctr);
    const char *h=[host UTF8String];
    { struct timeval tv; tv.tv_sec=5; tv.tv_usec=0; setsockopt(clientfd,SOL_SOCKET,SO_SNDTIMEO,&tv,sizeof(tv)); }  // Client-Write kurz -> abgebrochene Relays sterben schnell
    { int one=1; setsockopt(clientfd,SOL_SOCKET,SO_NOSIGPIPE,&one,sizeof(one)); }  // Player schließt -> EPIPE statt SIGPIPE
    YTLog(@"proxy relay host=%@ range=%@", host, rangeHdr?:@"-");
    if(mbedtls_ctr_drbg_seed(&ctr,mxEnt,NULL,(const unsigned char*)"ytpx",4)!=0){ YTLog(@"proxy drbg fail"); goto done; }
    if(mbedtls_net_connect(&srv,h,"443",MBEDTLS_NET_PROTO_TCP)!=0){ YTLog(@"proxy connect fail %@",host); goto done; }
    { struct timeval tv; tv.tv_sec=30; tv.tv_usec=0; setsockopt(srv.fd,SOL_SOCKET,SO_RCVTIMEO,&tv,sizeof(tv)); setsockopt(srv.fd,SOL_SOCKET,SO_SNDTIMEO,&tv,sizeof(tv));  // Upstream-Read großzügig (langsames WLAN)
      int one=1; setsockopt(srv.fd,SOL_SOCKET,SO_NOSIGPIPE,&one,sizeof(one)); }
    if(mbedtls_ssl_config_defaults(&conf,MBEDTLS_SSL_IS_CLIENT,MBEDTLS_SSL_TRANSPORT_STREAM,MBEDTLS_SSL_PRESET_DEFAULT)!=0) goto done;
    mbedtls_ssl_conf_authmode(&conf,MBEDTLS_SSL_VERIFY_NONE);   // iOS6 kennt Googles Root nicht -> wir prüfen nicht
    mbedtls_ssl_conf_rng(&conf,mbedtls_ctr_drbg_random,&ctr);
    if(mbedtls_ssl_setup(&ssl,&conf)!=0) goto done;
    mbedtls_ssl_set_hostname(&ssl,h);
    mbedtls_ssl_set_bio(&ssl,&srv,mbedtls_net_send,mbedtls_net_recv,NULL);
    { int hs; while((hs=mbedtls_ssl_handshake(&ssl))!=0){ if(hs!=MBEDTLS_ERR_SSL_WANT_READ&&hs!=MBEDTLS_ERR_SSL_WANT_WRITE){ YTLog(@"proxy handshake fail %@ (-0x%x)",host,-hs); goto done; } } YTLog(@"proxy TLS ok %@",host); }
    { NSMutableString *req=[NSMutableString stringWithFormat:@"GET %@ HTTP/1.1\r\nHost: %@\r\n",path,host];
      if(rangeHdr.length)[req appendFormat:@"%@\r\n",rangeHdr];
      [req appendString:@"User-Agent: com.google.android.apps.youtube.vr.oculus/1.60.19\r\nConnection: close\r\n\r\n"];
      NSData *rd=[req dataUsingEncoding:NSUTF8StringEncoding]; const unsigned char*wp=rd.bytes; size_t wl=rd.length,wo=0;
      while(wo<wl){ int w=mbedtls_ssl_write(&ssl,wp+wo,wl-wo); if(w<=0){ if(w==MBEDTLS_ERR_SSL_WANT_READ||w==MBEDTLS_ERR_SSL_WANT_WRITE)continue; goto done; } wo+=w; } }
    { unsigned char buf[16384]; long total=0;
      for(;;){ int rr=mbedtls_ssl_read(&ssl,buf,sizeof(buf)); if(rr==MBEDTLS_ERR_SSL_WANT_READ||rr==MBEDTLS_ERR_SSL_WANT_WRITE)continue; if(rr<=0)break;
        total+=rr; int wo=0; while(wo<rr){ int w=(int)write(clientfd,buf+wo,rr-wo); if(w<=0){ YTLog(@"proxy client write fail nach %ld B",total); goto done; } wo+=w; } }
      YTLog(@"proxy relay fertig %@ -> %ld B",host,total); }
done:
    mbedtls_ssl_close_notify(&ssl);
    mbedtls_net_free(&srv); mbedtls_ssl_free(&ssl); mbedtls_ssl_config_free(&conf); mbedtls_ctr_drbg_free(&ctr);
}

static void handle(int clientfd){
    @autoreleasepool {
        // Client, der verbindet aber nichts schickt, darf keinen Relay-Platz ewig blockieren
        { struct timeval tv; tv.tv_sec=10; tv.tv_usec=0; setsockopt(clientfd,SOL_SOCKET,SO_RCVTIMEO,&tv,sizeof(tv)); }
        NSString *hdrs=readHeaders(clientfd);
        NSString *remote=nil, *rangeHdr=nil;
        NSArray *lines=[hdrs componentsSeparatedByString:@"\r\n"];
        for(NSString *ln in lines){
            if([ln hasPrefix:@"GET "]){
                NSRange a=[ln rangeOfString:@"u="]; if(a.location!=NSNotFound){
                    NSString *rest=[ln substringFromIndex:a.location+2];
                    NSRange sp=[rest rangeOfString:@" "]; if(sp.location!=NSNotFound) rest=[rest substringToIndex:sp.location];
                    const char *cs=[rest UTF8String]; remote=b64urlDec(cs,(int)strlen(cs));
                }
            } else if([[ln lowercaseString] hasPrefix:@"range:"]) rangeHdr=ln;
        }
        YTLog(@"proxy request remote=%@", remote.length?[remote substringToIndex:MIN((NSUInteger)60,remote.length)]:@"(KEINE!)");
        if(remote.length) relay(clientfd, remote, rangeHdr);
        close(clientfd);
    }
}

@implementation YTProxy
+ (void)start {
    if(gListen>=0) return;
    int s=socket(AF_INET,SOCK_STREAM,0); if(s<0) return;
    int yes=1; setsockopt(s,SOL_SOCKET,SO_REUSEADDR,&yes,sizeof(yes));
    struct sockaddr_in a; memset(&a,0,sizeof(a)); a.sin_family=AF_INET; a.sin_port=htons(PROXY_PORT); a.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
    if(bind(s,(struct sockaddr*)&a,sizeof(a))!=0){ YTLog(@"proxy BIND FAIL port %d (errno %d)",PROXY_PORT,errno); close(s); return; }
    if(listen(s,8)!=0){ YTLog(@"proxy LISTEN FAIL"); close(s); return; }
    gListen=s; YTLog(@"proxy gestartet auf 127.0.0.1:%d",PROXY_PORT);
    // eigene konkurrierende Queue (nicht die globale -> Haupt-Thread/Bilder bleiben frei).
    // Max. PROXY_MAX_RELAYS gleichzeitig: weitere Verbindungen warten (Warteschlange); alte Relays
    // geben ihren Platz über die Socket-Timeouts sicher frei (kein Deadlock). Kommt in
    // PROXY_SLOT_WAIT_S kein Platz frei -> sauberes 503, der Player fragt neu an.
    static dispatch_queue_t pq; pq=dispatch_queue_create("mesh.yt.proxy",DISPATCH_QUEUE_CONCURRENT);
    static dispatch_semaphore_t slots; slots=dispatch_semaphore_create(PROXY_MAX_RELAYS);
    dispatch_async(dispatch_get_global_queue(0,0), ^{
        for(;;){ int c=accept(gListen,NULL,NULL); if(c<0)continue;
            { int one=1; setsockopt(c,SOL_SOCKET,SO_NOSIGPIPE,&one,sizeof(one)); }
            if(dispatch_semaphore_wait(slots,dispatch_time(DISPATCH_TIME_NOW,(int64_t)PROXY_SLOT_WAIT_S*NSEC_PER_SEC))!=0){
                YTLog(@"proxy voll -> 503");
                static const char busy[]="HTTP/1.1 503 Service Unavailable\r\nRetry-After: 1\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
                struct timeval tv; tv.tv_sec=2; tv.tv_usec=0; setsockopt(c,SOL_SOCKET,SO_SNDTIMEO,&tv,sizeof(tv));
                (void)write(c,busy,sizeof(busy)-1); close(c); continue;
            }
            dispatch_async(pq, ^{ handle(c); dispatch_semaphore_signal(slots); });
        }
    });
}
+ (NSString *)localURLFor:(NSString *)remoteHTTPSURL {
    if(!remoteHTTPSURL.length) return nil;
    return [NSString stringWithFormat:@"http://127.0.0.1:%d/v.mp4?u=%@",PROXY_PORT,b64urlEnc(remoteHTTPSURL)];
}
@end
