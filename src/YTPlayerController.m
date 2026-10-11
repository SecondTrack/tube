#import "YTPlayerController.h"
#import "YTTheme.h"
#import "YTApi.h"
#import "YTProxy.h"
#import "YTLog.h"
#import "MeshL10n.h"
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>

@interface YTPlayerController () <UIWebViewDelegate, UITableViewDataSource, UITableViewDelegate>
@end

@implementation YTPlayerController {
    NSString *_vid, *_title, *_author, *_avatarURL;
    NSString *_videoURL, *_audioURL;   // bereits als lokale Proxy-URLs
    MPMoviePlayerController *_mp;
    UIWebView *_web;
    UISegmentedControl *_mode;
    UILabel *_titleLbl, *_metaLbl, *_chanLbl, *_statusLbl;
    UIImageView *_avatarImg;
    UIActivityIndicatorView *_spin;
    UIView *_stage;
    BOOL _audioMode;
    // eigene YouTube-Controls
    UIView *_ctrls, *_progTrack, *_progFill, *_knob, *_playBtn;
    UILabel *_tCur, *_tDur;
    UIButton *_fsBtn;
    NSTimer *_timer;
    CGFloat _trackX, _trackW;
    BOOL _ctrlsShown, _seeking;
    UITableView *_cTable;      // Kommentare
    NSArray *_comments;
    NSCache *_cImgs;
    CGFloat _sh, _sy;
    BOOL _fs; UIView *_fsBox;   // eigenes Vollbild
}

- (id)initWithVideoId:(NSString *)videoId title:(NSString *)title author:(NSString *)author avatar:(NSString *)avatar {
    if((self=[super init])){ _vid=videoId; _title=title?:@""; _author=author?:@""; _avatarURL=avatar?:@""; }
    return self;
}

- (void)loadView {
    self.view=[[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.view.backgroundColor=[YTTheme bg];
    CGFloat W=self.view.bounds.size.width, H=self.view.bounds.size.height;
    _sh=W*9.0/16.0; _sy=20; _cImgs=[[NSCache alloc] init]; _cImgs.countLimit=60;

    _stage=[[UIView alloc] initWithFrame:CGRectMake(0,_sy,W,_sh)]; _stage.backgroundColor=[UIColor blackColor]; [self.view addSubview:_stage];
    _spin=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    _spin.center=CGPointMake(W/2,_sh/2); _spin.hidesWhenStopped=YES; _spin.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin|UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleBottomMargin; [_stage addSubview:_spin];
    _statusLbl=[[UILabel alloc] initWithFrame:CGRectMake(16,0,W-32,_sh)]; _statusLbl.numberOfLines=0; _statusLbl.textColor=[YTTheme muted]; _statusLbl.font=[UIFont systemFontOfSize:12]; _statusLbl.textAlignment=NSTextAlignmentCenter; _statusLbl.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; [_stage addSubview:_statusLbl];

    // Kommentar-Tabelle (füllt unter dem Video), mit Kopf = Titel/Kanal
    _cTable=[[UITableView alloc] initWithFrame:CGRectMake(0,_sy+_sh,W,H-_sy-_sh) style:UITableViewStylePlain];
    _cTable.backgroundColor=[YTTheme bg]; _cTable.separatorColor=[YTTheme line]; _cTable.dataSource=self; _cTable.delegate=self;
    _cTable.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    _cTable.tableHeaderView=[self buildHeader]; [self.view addSubview:_cTable];

    // Zurück-Chevron über dem Video
    UIButton *back=[UIButton buttonWithType:UIButtonTypeCustom]; back.frame=CGRectMake(2,_sy+2,44,34);
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(44,34),NO,0); UIBezierPath*ch=[UIBezierPath bezierPath]; ch.lineWidth=2.5; ch.lineCapStyle=kCGLineCapRound; ch.lineJoinStyle=kCGLineJoinRound; [ch moveToPoint:CGPointMake(26,10)];[ch addLineToPoint:CGPointMake(16,17)];[ch addLineToPoint:CGPointMake(26,24)]; [[UIColor whiteColor] setStroke]; [ch stroke]; UIImage*ci=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
    [back setImage:ci forState:UIControlStateNormal]; [back addTarget:self action:@selector(goBack) forControlEvents:UIControlEventTouchUpInside]; [self.view addSubview:back];
}

- (UIView *)buildHeader {
    CGFloat W=self.view.bounds.size.width;
    UIView *h=[[UIView alloc] initWithFrame:CGRectMake(0,0,W,0)]; h.backgroundColor=[YTTheme bg];
    CGFloat y=12;
    _titleLbl=[[UILabel alloc] initWithFrame:CGRectMake(12,y,W-24,40)]; _titleLbl.numberOfLines=2; _titleLbl.font=[UIFont boldSystemFontOfSize:15]; _titleLbl.textColor=[YTTheme ink]; _titleLbl.text=_title; [h addSubview:_titleLbl]; y+=44;
    _metaLbl=[[UILabel alloc] initWithFrame:CGRectMake(12,y,W-24,16)]; _metaLbl.font=[UIFont systemFontOfSize:12]; _metaLbl.textColor=[YTTheme muted]; [h addSubview:_metaLbl]; y+=24;
    _avatarImg=[[UIImageView alloc] initWithFrame:CGRectMake(12,y,34,34)]; _avatarImg.backgroundColor=[YTTheme card]; _avatarImg.layer.cornerRadius=17; _avatarImg.clipsToBounds=YES; _avatarImg.contentMode=UIViewContentModeScaleAspectFill; [h addSubview:_avatarImg];
    _chanLbl=[[UILabel alloc] initWithFrame:CGRectMake(54,y+7,W-54-70,20)]; _chanLbl.font=[UIFont boldSystemFontOfSize:13]; _chanLbl.textColor=[YTTheme ink]; _chanLbl.text=_author; [h addSubview:_chanLbl];
    if(_avatarURL.length) dispatch_async(dispatch_get_global_queue(0,0), ^{ NSData *d=[NSData dataWithContentsOfURL:[NSURL URLWithString:_avatarURL]]; UIImage *im=d?[UIImage imageWithData:d]:nil; if(im) dispatch_async(dispatch_get_main_queue(), ^{ _avatarImg.image=im; }); });
    UIButton *shr=[UIButton buttonWithType:UIButtonTypeCustom]; shr.frame=CGRectMake(W-54,y+2,42,30); [shr setImage:[self actionIcon:@"share"] forState:UIControlStateNormal]; [shr addTarget:self action:@selector(share) forControlEvents:UIControlEventTouchUpInside]; [h addSubview:shr];
    y+=46;
    UIView *sep=[[UIView alloc] initWithFrame:CGRectMake(0,y,W,0.5)]; sep.backgroundColor=[YTTheme line]; [h addSubview:sep];
    UILabel *cl=[[UILabel alloc] initWithFrame:CGRectMake(12,y+8,W-24,20)]; cl.text=L(@"Comments"); cl.font=[UIFont boldSystemFontOfSize:14]; cl.textColor=[YTTheme ink]; [h addSubview:cl]; y+=34;
    h.frame=CGRectMake(0,0,W,y);
    return h;
}

// ---- Kommentare-Tabelle ----
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return _comments.count; }
- (CGFloat)tableView:(UITableView *)t heightForRowAtIndexPath:(NSIndexPath *)ip {
    NSDictionary *c=_comments[ip.row]; NSString *txt=c[@"text"]?:@"";
    CGFloat w=t.bounds.size.width-54;
    CGSize sz=[txt sizeWithFont:[UIFont systemFontOfSize:13] constrainedToSize:CGSizeMake(w,10000) lineBreakMode:NSLineBreakByWordWrapping];
    return MAX(54.0, sz.height+40);
}
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c=[tv dequeueReusableCellWithIdentifier:@"c"];
    if(!c){ c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"c"]; c.backgroundColor=[YTTheme bg]; c.selectionStyle=UITableViewCellSelectionStyleNone;
        UIImageView *av=[[UIImageView alloc] initWithFrame:CGRectMake(12,10,30,30)]; av.tag=1; av.backgroundColor=[YTTheme card]; av.layer.cornerRadius=15; av.clipsToBounds=YES; av.contentMode=UIViewContentModeScaleAspectFill; [c.contentView addSubview:av];
        UILabel *au=[[UILabel alloc] initWithFrame:CGRectMake(52,8,tv.bounds.size.width-64,16)]; au.tag=2; au.font=[UIFont boldSystemFontOfSize:12]; au.textColor=[YTTheme muted]; [c.contentView addSubview:au];
        UILabel *tx=[[UILabel alloc] initWithFrame:CGRectMake(52,26,tv.bounds.size.width-64,16)]; tx.tag=3; tx.numberOfLines=0; tx.font=[UIFont systemFontOfSize:13]; tx.textColor=[YTTheme ink]; [c.contentView addSubview:tx];
    }
    NSDictionary *cm=_comments[ip.row];
    ((UILabel*)[c.contentView viewWithTag:2]).text=[cm[@"likes"] length]?[NSString stringWithFormat:@"%@   ▲ %@",cm[@"author"],cm[@"likes"]]:cm[@"author"];
    UILabel *tx=(UILabel*)[c.contentView viewWithTag:3]; tx.text=cm[@"text"];
    CGFloat w=tv.bounds.size.width-64; CGSize sz=[cm[@"text"] sizeWithFont:[UIFont systemFontOfSize:13] constrainedToSize:CGSizeMake(w,10000) lineBreakMode:NSLineBreakByWordWrapping];
    tx.frame=CGRectMake(52,26,w,sz.height);
    UIImageView *av=(UIImageView*)[c.contentView viewWithTag:1]; av.image=nil;
    NSString *url=cm[@"avatar"];
    if(url.length){ UIImage *ci=[_cImgs objectForKey:url]; if(ci) av.image=ci; else dispatch_async(dispatch_get_global_queue(0,0), ^{ NSData*d=[NSData dataWithContentsOfURL:[NSURL URLWithString:url]]; UIImage*im=d?[UIImage imageWithData:d]:nil; if(im){ [_cImgs setObject:im forKey:url]; dispatch_async(dispatch_get_main_queue(), ^{ UITableViewCell*cc=[tv cellForRowAtIndexPath:ip]; if(cc)((UIImageView*)[cc.contentView viewWithTag:1]).image=im; }); } }); }
    return c;
}

- (UIImage *)actionIcon:(NSString *)k {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(26,26),NO,0);
    UIBezierPath *p=[UIBezierPath bezierPath]; p.lineWidth=1.8; p.lineJoinStyle=kCGLineJoinRound; p.lineCapStyle=kCGLineCapRound; [[YTTheme ink] setStroke];
    if([k isEqualToString:@"like"]){ [p moveToPoint:CGPointMake(6,12)];[p addLineToPoint:CGPointMake(6,22)];[p addLineToPoint:CGPointMake(18,22)];[p addLineToPoint:CGPointMake(21,13)];[p addLineToPoint:CGPointMake(13,13)];[p addLineToPoint:CGPointMake(14,6)];[p addLineToPoint:CGPointMake(10,11)];[p addLineToPoint:CGPointMake(6,12)]; }
    else if([k isEqualToString:@"dislike"]){ [p moveToPoint:CGPointMake(6,14)];[p addLineToPoint:CGPointMake(6,4)];[p addLineToPoint:CGPointMake(18,4)];[p addLineToPoint:CGPointMake(21,13)];[p addLineToPoint:CGPointMake(13,13)];[p addLineToPoint:CGPointMake(14,20)];[p addLineToPoint:CGPointMake(10,15)];[p addLineToPoint:CGPointMake(6,14)]; }
    else if([k isEqualToString:@"share"]){ [p moveToPoint:CGPointMake(5,13)];[p addLineToPoint:CGPointMake(5,21)];[p addLineToPoint:CGPointMake(21,21)];[p addLineToPoint:CGPointMake(21,13)]; [p moveToPoint:CGPointMake(13,4)];[p addLineToPoint:CGPointMake(13,16)]; [p moveToPoint:CGPointMake(8,9)];[p addLineToPoint:CGPointMake(13,4)];[p addLineToPoint:CGPointMake(18,9)]; }
    else { [p moveToPoint:CGPointMake(7,4)];[p addLineToPoint:CGPointMake(19,4)];[p addLineToPoint:CGPointMake(19,22)];[p addLineToPoint:CGPointMake(13,17)];[p addLineToPoint:CGPointMake(7,22)];[p closePath]; }
    [p stroke]; UIImage *img=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return img;
}
- (void)actionTap:(UIButton *)b { if(b.tag==102) [self share]; else [self needLogin]; }
- (void)needLogin { [[[UIAlertView alloc] initWithTitle:nil message:L(@"You need to be signed in for that.") delegate:nil cancelButtonTitle:L(@"OK") otherButtonTitles:nil] show]; }
- (void)share {
    NSString *link=[@"https://youtu.be/" stringByAppendingString:_vid?:@""];
    UIActivityViewController *a=[[UIActivityViewController alloc] initWithActivityItems:@[link] applicationActivities:nil];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)goBack { [self.navigationController popViewControllerAnimated:YES]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    [_spin startAnimating]; _statusLbl.text=@"";   // nur Spinner beim Laden (Text würde ihn überlagern); Text nur für Fehler
    [YTApi streams:_vid completion:^(NSString *v,NSString *a,NSString *title,NSString *author,NSString *err){
        if(err){ [_spin stopAnimating]; _statusLbl.text=err; return; }
        if(title.length){ _titleLbl.text=title; [self resizeHeader]; } if(author.length){ _author=author; _chanLbl.text=_author; }
        _videoURL=[YTProxy localURLFor:v]; _audioURL=[YTProxy localURLFor:a];   // über lokalen Proxy
        if(!_videoURL) _audioMode=YES;
        [self startPlayback:0];
    }];
    // Kommentare laden
    [YTApi comments:_vid completion:^(NSArray *cs){ _comments=cs; [_cTable reloadData]; }];
    // Geräte-Drehung selbst abfangen -> eigenes Vollbild (App bleibt Hochformat)
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(deviceRotated) name:UIDeviceOrientationDidChangeNotification object:nil];
}
- (void)deviceRotated {
    UIDeviceOrientation o=[UIDevice currentDevice].orientation;
    if(o==UIDeviceOrientationLandscapeLeft || o==UIDeviceOrientationLandscapeRight){
        CGFloat ang=(o==UIDeviceOrientationLandscapeLeft)? M_PI_2 : -M_PI_2;
        if(!_fs)[self enterFS:ang]; else [self rotateFS:ang];
    } else if(o==UIDeviceOrientationPortrait){
        if(_fs)[self exitFS];
    }
}
- (void)resizeHeader {
    CGFloat W=self.view.bounds.size.width;
    CGSize sz=[_titleLbl.text sizeWithFont:_titleLbl.font constrainedToSize:CGSizeMake(W-24,60) lineBreakMode:NSLineBreakByWordWrapping];
    // Titel kann jetzt 2 Zeilen brauchen -> Kopf ggf. neu setzen (nur wenn Tabelle schon da)
    (void)sz;  // Layout bleibt 2-zeilig; Platz ist reserviert
}

// Fallback: iOS-eigenes WebKit lädt den YouTube-Embed-Player direkt (echter Browser auf dem Gerät)
- (void)tryEmbed {
    _statusLbl.text=L(@"Trying web player …");
    [self teardown];
    _web=[[UIWebView alloc] initWithFrame:_stage.bounds];
    _web.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    _web.backgroundColor=[UIColor blackColor]; _web.opaque=NO; _web.scrollView.scrollEnabled=NO;
    _web.allowsInlineMediaPlayback=YES; _web.mediaPlaybackRequiresUserAction=NO; _web.delegate=self;
    [_stage addSubview:_web];
    NSString *u=[NSString stringWithFormat:@"https://www.youtube.com/embed/%@?playsinline=1&autoplay=1&fs=1",_vid];
    YTLog(@"embed load %@",u);
    [_web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:u]]];
}
- (void)webViewDidFinishLoad:(UIWebView *)wv { YTLog(@"embed didFinishLoad"); [_spin stopAnimating]; _statusLbl.text=@""; }
- (void)webView:(UIWebView *)wv didFailLoadWithError:(NSError *)e { YTLog(@"embed FAIL %@",e.localizedDescription); [_spin stopAnimating]; _statusLbl.text=L(@"YouTube won't play this video without a modern browser."); }

- (void)modeChanged { NSTimeInterval t=_mp?_mp.currentPlaybackTime:0; _audioMode=(_mode.selectedSegmentIndex==1); [self startPlayback:t]; }

- (void)startPlayback:(NSTimeInterval)startAt {
    NSString *url=_audioMode?(_audioURL?:_videoURL):(_videoURL?:_audioURL);
    if(!url.length){ [_spin stopAnimating]; _statusLbl.text=L(@"No stream URL"); return; }
    YTLog(@"player startPlayback audioMode=%d url=%@", _audioMode, [url substringToIndex:MIN((NSUInteger)50,url.length)]);
    [self teardown];
    AVAudioSession *as=[AVAudioSession sharedInstance];
    [as setCategory:AVAudioSessionCategoryPlayback error:NULL]; [as setActive:YES error:NULL];
    _mp=[[MPMoviePlayerController alloc] initWithContentURL:[NSURL URLWithString:url]];
    _mp.movieSourceType=MPMovieSourceTypeUnknown;   // progressives MP4, NICHT Streaming(=HLS) -> sonst AVFoundation-Crash
    _mp.controlStyle=MPMovieControlStyleNone; _mp.shouldAutoplay=YES;   // Apple-Controls AUS -> eigener YouTube-Look
    _mp.view.frame=_stage.bounds; _mp.view.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; [_stage addSubview:_mp.view];
    if(_audioMode){ UILabel *n=[[UILabel alloc] initWithFrame:_stage.bounds]; n.tag=77; n.text=L(@"♪  Audio only"); n.textColor=[YTTheme muted]; n.font=[UIFont systemFontOfSize:15]; n.textAlignment=NSTextAlignmentCenter; [_stage addSubview:n]; }
    [self buildControls];
    [_stage bringSubviewToFront:_spin]; [_stage bringSubviewToFront:_statusLbl];   // über dem Video, damit Laden sichtbar ist
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(stateChanged:) name:MPMoviePlayerLoadStateDidChangeNotification object:_mp];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(finished:) name:MPMoviePlayerPlaybackDidFinishNotification object:_mp];
    [_mp prepareToPlay]; if(startAt>0)_mp.initialPlaybackTime=startAt; [_mp play];
    _timer=[NSTimer scheduledTimerWithTimeInterval:0.4 target:self selector:@selector(tick) userInfo:nil repeats:YES];
}

// ---- eigene YouTube-Steuerung über dem Video ----
- (void)buildControls {
    CGFloat W=_stage.bounds.size.width, H=_stage.bounds.size.height;
    _ctrls=[[UIView alloc] initWithFrame:_stage.bounds];
    _ctrls.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; [_stage addSubview:_ctrls];
    // Tipp aufs Video -> Controls ein/aus
    UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleCtrls)]; [_ctrls addGestureRecognizer:tap];
    // großer Play/Pause-Button in der Mitte
    _playBtn=[[UIView alloc] initWithFrame:CGRectMake(W/2-26,H/2-26,52,52)]; _playBtn.backgroundColor=[UIColor colorWithWhite:0 alpha:0.5]; _playBtn.layer.cornerRadius=26;
    _playBtn.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin|UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleBottomMargin;
    UIButton *pb=[UIButton buttonWithType:UIButtonTypeCustom]; pb.frame=_playBtn.bounds; [pb addTarget:self action:@selector(togglePlay) forControlEvents:UIControlEventTouchUpInside]; [_playBtn addSubview:pb];
    [_ctrls addSubview:_playBtn];
    // untere Leiste: Zeit | roter Scrubber | Zeit | Vollbild
    CGFloat by=H-24;
    _tCur=[[UILabel alloc] initWithFrame:CGRectMake(6,by,38,20)]; _tCur.text=@"0:00"; _tCur.font=[UIFont systemFontOfSize:10]; _tCur.textColor=[UIColor whiteColor]; _tCur.autoresizingMask=UIViewAutoresizingFlexibleTopMargin; [_ctrls addSubview:_tCur];
    _tDur=[[UILabel alloc] initWithFrame:CGRectMake(W-66,by,36,20)]; _tDur.text=@"0:00"; _tDur.font=[UIFont systemFontOfSize:10]; _tDur.textColor=[UIColor whiteColor]; _tDur.textAlignment=NSTextAlignmentRight; _tDur.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleTopMargin; [_ctrls addSubview:_tDur];
    _trackX=46; _trackW=W-46-70;
    _progTrack=[[UIView alloc] initWithFrame:CGRectMake(_trackX,by+8,_trackW,3)]; _progTrack.backgroundColor=[UIColor colorWithWhite:1 alpha:0.35]; _progTrack.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleTopMargin; [_ctrls addSubview:_progTrack];
    _progFill=[[UIView alloc] initWithFrame:CGRectMake(_trackX,by+8,0,3)]; _progFill.backgroundColor=[YTTheme red]; _progFill.autoresizingMask=UIViewAutoresizingFlexibleTopMargin; [_ctrls addSubview:_progFill];
    _knob=[[UIView alloc] initWithFrame:CGRectMake(_trackX-5,by+4.5,10,10)]; _knob.backgroundColor=[YTTheme red]; _knob.layer.cornerRadius=5; _knob.autoresizingMask=UIViewAutoresizingFlexibleTopMargin; [_ctrls addSubview:_knob];
    UIView *seek=[[UIView alloc] initWithFrame:CGRectMake(_trackX-10,by,_trackW+20,24)]; seek.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleTopMargin;
    [seek addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleSeek:)]];
    [seek addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleSeek:)]]; [_ctrls addSubview:seek];
    _fsBtn=[UIButton buttonWithType:UIButtonTypeCustom]; _fsBtn.frame=CGRectMake(W-28,by-1,24,22); _fsBtn.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleTopMargin;
    [_fsBtn setImage:[self fsIcon] forState:UIControlStateNormal]; [_fsBtn addTarget:self action:@selector(toggleFullscreen) forControlEvents:UIControlEventTouchUpInside]; [_ctrls addSubview:_fsBtn];
    _ctrlsShown=YES; [self drawPlayIcon]; [self scheduleHide];
}
- (UIImage *)fsIcon {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(22,22),NO,0); [[UIColor whiteColor] setStroke]; UIBezierPath*p=[UIBezierPath bezierPath]; p.lineWidth=1.8; p.lineCapStyle=kCGLineCapRound;
    [p moveToPoint:CGPointMake(3,8)];[p addLineToPoint:CGPointMake(3,3)];[p addLineToPoint:CGPointMake(8,3)];
    [p moveToPoint:CGPointMake(14,3)];[p addLineToPoint:CGPointMake(19,3)];[p addLineToPoint:CGPointMake(19,8)];
    [p moveToPoint:CGPointMake(19,14)];[p addLineToPoint:CGPointMake(19,19)];[p addLineToPoint:CGPointMake(14,19)];
    [p moveToPoint:CGPointMake(8,19)];[p addLineToPoint:CGPointMake(3,19)];[p addLineToPoint:CGPointMake(3,14)]; [p stroke];
    UIImage*i=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return i;
}
- (void)drawPlayIcon {
    for(UIView*v in [_playBtn.subviews copy]) if(v.tag==9)[v removeFromSuperview];
    UIView *ic=[[UIView alloc] initWithFrame:_playBtn.bounds]; ic.tag=9; ic.userInteractionEnabled=NO;
    if([_mp playbackState]==MPMoviePlaybackStatePlaying){ for(int i=0;i<2;i++){ UIView*b=[[UIView alloc] initWithFrame:CGRectMake(18+i*10,16,6,20)]; b.backgroundColor=[UIColor whiteColor]; [ic addSubview:b]; } }
    else { UIImageView*tv=[[UIImageView alloc] initWithFrame:ic.bounds]; UIGraphicsBeginImageContextWithOptions(ic.bounds.size,NO,0); UIBezierPath*t=[UIBezierPath bezierPath]; [t moveToPoint:CGPointMake(20,15)];[t addLineToPoint:CGPointMake(20,37)];[t addLineToPoint:CGPointMake(38,26)];[t closePath]; [[UIColor whiteColor] setFill]; [t fill]; tv.image=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); [ic addSubview:tv]; }
    [_playBtn addSubview:ic];
}
- (void)togglePlay { if([_mp playbackState]==MPMoviePlaybackStatePlaying)[_mp pause]; else [_mp play]; [self drawPlayIcon]; [self showCtrls]; }
// Eigenes Vollbild: dreht NUR das Video (+ meine Controls) ins Querformat, kein Apple-Player.
- (void)toggleFullscreen { if(_fs)[self exitFS]; else [self enterFS:M_PI_2]; }
- (void)enterFS:(CGFloat)angle {
    _fs=YES;
    UIWindow *win=self.view.window?:[[UIApplication sharedApplication] keyWindow]; if(!win)return;
    CGRect wb=win.bounds;
    _fsBox=[[UIView alloc] initWithFrame:wb]; _fsBox.backgroundColor=[UIColor blackColor]; [win addSubview:_fsBox];
    [_fsBox addSubview:_mp.view]; [_fsBox addSubview:_ctrls];
    [self rotateFS:angle];
    [self showCtrls];
}
- (void)rotateFS:(CGFloat)angle {
    UIWindow *win=_fsBox.window?:self.view.window; CGRect wb=win.bounds;
    CGFloat w=wb.size.height, h=wb.size.width; CGPoint c=CGPointMake(wb.size.width/2,wb.size.height/2);
    _mp.view.transform=CGAffineTransformIdentity; _mp.view.bounds=CGRectMake(0,0,w,h); _mp.view.center=c; _mp.view.transform=CGAffineTransformMakeRotation(angle);
    _ctrls.transform=CGAffineTransformIdentity; _ctrls.bounds=CGRectMake(0,0,w,h); _ctrls.center=c; _ctrls.transform=CGAffineTransformMakeRotation(angle);
}
- (void)exitFS {
    _fs=NO;
    _mp.view.transform=CGAffineTransformIdentity; _mp.view.frame=_stage.bounds; [_stage addSubview:_mp.view];
    _ctrls.transform=CGAffineTransformIdentity; _ctrls.frame=_stage.bounds; [_stage addSubview:_ctrls];
    if(_fsBox){ [_fsBox removeFromSuperview]; _fsBox=nil; }
    [_stage bringSubviewToFront:_spin]; [_stage bringSubviewToFront:_statusLbl];
    [self showCtrls];
}
- (void)toggleCtrls { if(_ctrlsShown){ [self hideCtrls]; } else { [self showCtrls]; } }
- (void)showCtrls { _ctrlsShown=YES; [UIView animateWithDuration:0.15 animations:^{ _playBtn.alpha=1; _tCur.alpha=1;_tDur.alpha=1;_progTrack.alpha=1;_progFill.alpha=1;_knob.alpha=1;_fsBtn.alpha=1; }]; [self scheduleHide]; }
- (void)hideCtrls { _ctrlsShown=NO; [UIView animateWithDuration:0.25 animations:^{ _playBtn.alpha=0; _tCur.alpha=0;_tDur.alpha=0;_progTrack.alpha=0.0;_progFill.alpha=0.0;_knob.alpha=0;_fsBtn.alpha=0; }]; }
- (void)scheduleHide { [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideCtrls) object:nil]; [self performSelector:@selector(hideCtrls) withObject:nil afterDelay:3.5]; }
- (NSString *)fmt:(double)s { if(s<0||s!=s)s=0; int m=(int)s/60,se=(int)s%60; return [NSString stringWithFormat:@"%d:%02d",m,se]; }
- (void)tick {
    double cur=_mp.currentPlaybackTime, dur=_mp.duration;
    CGFloat tx=_progTrack.frame.origin.x, tw=_progTrack.frame.size.width, ty=_progTrack.frame.origin.y, ky=_progTrack.center.y;
    if(!_seeking && dur>0){ double f=cur/dur; if(f<0)f=0; if(f>1)f=1; CGFloat w=tw*f;
        _progFill.frame=CGRectMake(tx,ty,w,3); _knob.center=CGPointMake(tx+w,ky);
        _tCur.text=[self fmt:cur]; _tDur.text=[self fmt:dur]; }
    [self drawPlayIcon];
}
- (void)handleSeek:(UIGestureRecognizer *)g {
    double dur=_mp.duration; if(dur<=0) return;
    CGFloat tx=_progTrack.frame.origin.x, tw=_progTrack.frame.size.width, ty=_progTrack.frame.origin.y, ky=_progTrack.center.y;
    CGPoint p=[g locationInView:_ctrls]; double f=(p.x-tx)/tw; if(f<0)f=0; if(f>1)f=1;
    CGFloat w=tw*f; _progFill.frame=CGRectMake(tx,ty,w,3); _knob.center=CGPointMake(tx+w,ky); _tCur.text=[self fmt:f*dur];
    _seeking=(g.state==UIGestureRecognizerStateBegan||g.state==UIGestureRecognizerStateChanged);
    if([g isKindOfClass:[UITapGestureRecognizer class]] || g.state==UIGestureRecognizerStateEnded){ _mp.currentPlaybackTime=f*dur; _seeking=NO; [self showCtrls]; }
}
- (void)stateChanged:(NSNotification *)n { YTLog(@"player loadState=%d", (int)_mp.loadState); if(_mp.loadState & (MPMovieLoadStatePlayable|MPMovieLoadStatePlaythroughOK)){ [_spin stopAnimating]; _statusLbl.text=@""; } }
- (void)finished:(NSNotification *)n {
    NSInteger r=[n.userInfo[MPMoviePlayerPlaybackDidFinishReasonUserInfoKey] integerValue];
    YTLog(@"player finished reason=%ld", (long)r);
    if(r==MPMovieFinishReasonPlaybackError){ [_spin stopAnimating]; _statusLbl.text=L(@"Playback error"); }
}
- (void)teardown {
    if(_timer){ [_timer invalidate]; _timer=nil; }
    if(_fsBox){ [_fsBox removeFromSuperview]; _fsBox=nil; } _fs=NO;
    if(_ctrls){ _ctrls.transform=CGAffineTransformIdentity; [_ctrls removeFromSuperview]; _ctrls=nil; }
    if(_web){ _web.delegate=nil; [_web stopLoading]; [_web removeFromSuperview]; _web=nil; }
    if(_mp){ [[NSNotificationCenter defaultCenter] removeObserver:self name:MPMoviePlayerLoadStateDidChangeNotification object:_mp]; [[NSNotificationCenter defaultCenter] removeObserver:self name:MPMoviePlayerPlaybackDidFinishNotification object:_mp]; [_mp stop]; [_mp.view removeFromSuperview]; _mp=nil; }
    for(UIView *v in [_stage.subviews copy]) if(v.tag==77)[v removeFromSuperview];
}
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; [self teardown]; [[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications]; }
- (NSUInteger)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }   // Screen Hochformat; MPMoviePlayer-Vollbild dreht selbst
- (BOOL)shouldAutorotate { return NO; }
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
@end
