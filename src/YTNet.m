#import "YTNet.h"
#import "mbedtls/ssl.h"
#import "mbedtls/net_sockets.h"
#import "mbedtls/ctr_drbg.h"
#import <sys/socket.h>
#import <sys/time.h>

#define YT_NET_TIMEOUT_S 15   // hängende Verbindung (WLAN weg) -> nach 15 s normaler Fehler statt ewig blockieren

// Socket absichern: kein SIGPIPE beim Schreiben auf tote Verbindung, Lese-/Schreib-Timeout.
static void ytSockOpts(int fd){
    if(fd<0) return;
    int one=1; setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&one,sizeof(one));
    struct timeval tv; tv.tv_sec=YT_NET_TIMEOUT_S; tv.tv_usec=0;
    setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&tv,sizeof(tv)); setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&tv,sizeof(tv));
}

static int mxEntropy(void*d,unsigned char*o,size_t n){ (void)d; for(size_t i=0;i<n;i++)o[i]=arc4random()&0xff; return 0; }

static NSData* dechunk(NSData*d){
    NSMutableData*out=[NSMutableData data]; const unsigned char*b=d.bytes; NSUInteger n=d.length,p=0;
    while(p<n){ NSUInteger e=p; while(e<n && b[e]!='\r')e++; if(e>=n)break;
        char tmp[16]; NSUInteger len=e-p; if(len>15)len=15; memcpy(tmp,b+p,len); tmp[len]=0;
        long sz=strtol(tmp,NULL,16); p=e+2; if(sz<=0)break; if(p+(NSUInteger)sz>n)sz=(long)(n-p);
        [out appendBytes:b+p length:sz]; p+=sz+2; }
    return out;
}

@implementation YTNet

+ (NSString *)enc:(NSString *)s {
    CFStringRef e=CFURLCreateStringByAddingPercentEscapes(NULL,(__bridge CFStringRef)s,NULL,
        CFSTR("!*'();:@&=+$,/?%#[]{}\" "),kCFStringEncodingUTF8);
    return (__bridge_transfer NSString *)e;
}

+ (NSData *)request:(NSString *)method host:(NSString *)host path:(NSString *)path
            headers:(NSArray *)headers body:(NSData *)body status:(int *)statusOut {
    if(statusOut)*statusOut=0;
    mbedtls_net_context srv; mbedtls_ssl_context ssl; mbedtls_ssl_config conf; mbedtls_ctr_drbg_context ctr;
    mbedtls_net_init(&srv); mbedtls_ssl_init(&ssl); mbedtls_ssl_config_init(&conf); mbedtls_ctr_drbg_init(&ctr);
    NSData*result=nil; const char*h=[host UTF8String];
    if(mbedtls_ctr_drbg_seed(&ctr,mxEntropy,NULL,(const unsigned char*)"mxcli",5)!=0) goto done;
    if(mbedtls_net_connect(&srv,h,"443",MBEDTLS_NET_PROTO_TCP)!=0) goto done;
    ytSockOpts(srv.fd);
    if(mbedtls_ssl_config_defaults(&conf,MBEDTLS_SSL_IS_CLIENT,MBEDTLS_SSL_TRANSPORT_STREAM,MBEDTLS_SSL_PRESET_DEFAULT)!=0) goto done;
    mbedtls_ssl_conf_authmode(&conf,MBEDTLS_SSL_VERIFY_NONE);
    mbedtls_ssl_conf_rng(&conf,mbedtls_ctr_drbg_random,&ctr);
    mbedtls_ssl_conf_read_timeout(&conf,YT_NET_TIMEOUT_S*1000);
    if(mbedtls_ssl_setup(&ssl,&conf)!=0) goto done;
    mbedtls_ssl_set_hostname(&ssl,h);
    mbedtls_ssl_set_bio(&ssl,&srv,mbedtls_net_send,NULL,mbedtls_net_recv_timeout);   // Lesen mit Timeout
    { int hs; while((hs=mbedtls_ssl_handshake(&ssl))!=0){ if(hs!=MBEDTLS_ERR_SSL_WANT_READ&&hs!=MBEDTLS_ERR_SSL_WANT_WRITE) goto done; } }
    { NSMutableString*req=[NSMutableString stringWithFormat:@"%@ %@ HTTP/1.1\r\nHost: %@\r\nConnection: close\r\n",method,path,host];
      for(NSString*x in headers)[req appendFormat:@"%@\r\n",x];
      [req appendFormat:@"Content-Length: %lu\r\n\r\n",(unsigned long)body.length];
      NSMutableData*rd=[[req dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
      if(body.length)[rd appendData:body];
      const unsigned char*wp=rd.bytes; size_t wl=rd.length,wo=0;
      while(wo<wl){ int w=mbedtls_ssl_write(&ssl,wp+wo,wl-wo); if(w<=0){ if(w==MBEDTLS_ERR_SSL_WANT_READ||w==MBEDTLS_ERR_SSL_WANT_WRITE)continue; goto done; } wo+=w; } }
    { NSMutableData*resp=[NSMutableData data]; unsigned char buf[8192];
      for(;;){ int rr=mbedtls_ssl_read(&ssl,buf,sizeof(buf)); if(rr==MBEDTLS_ERR_SSL_WANT_READ||rr==MBEDTLS_ERR_SSL_WANT_WRITE)continue;
        if(rr==MBEDTLS_ERR_SSL_TIMEOUT||rr==MBEDTLS_ERR_NET_RECV_FAILED) goto done;   // Timeout/Abbruch -> Fehler (nil), keine halbe Antwort
        if(rr<=0)break; [resp appendBytes:buf length:rr]; }
      NSData*sep=[@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
      NSRange sr=[resp rangeOfData:sep options:0 range:NSMakeRange(0,resp.length)];
      if(sr.location!=NSNotFound){
        NSString*hstr=[[NSString alloc] initWithData:[resp subdataWithRange:NSMakeRange(0,sr.location)] encoding:NSUTF8StringEncoding];
        if(statusOut){ NSArray*pp=[hstr componentsSeparatedByString:@" "]; if(pp.count>1)*statusOut=[pp[1] intValue]; }
        NSData*bd=[resp subdataWithRange:NSMakeRange(sr.location+4,resp.length-sr.location-4)];
        if([hstr rangeOfString:@"chunked" options:NSCaseInsensitiveSearch].location!=NSNotFound) bd=dechunk(bd);
        result=bd;
      }
    }
done:
    mbedtls_ssl_close_notify(&ssl);
    mbedtls_net_free(&srv); mbedtls_ssl_free(&ssl); mbedtls_ssl_config_free(&conf); mbedtls_ctr_drbg_free(&ctr);
    return result;
}

+ (id)json:(NSString *)method host:(NSString *)host path:(NSString *)path
    bearer:(NSString *)token jsonBody:(id)jsonBody status:(int *)status {
    NSMutableArray*hdr=[NSMutableArray array];
    if(token.length)[hdr addObject:[@"Authorization: Bearer " stringByAppendingString:token]];
    NSData*body=nil;
    if(jsonBody){ body=[NSJSONSerialization dataWithJSONObject:jsonBody options:0 error:NULL]; [hdr addObject:@"Content-Type: application/json"]; }
    int st=0; NSData*d=[self request:method host:host path:path headers:hdr body:body status:&st];
    if(status)*status=st;
    if(!d.length) return nil;
    return [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL];
}

@end
