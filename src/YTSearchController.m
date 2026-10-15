#import "YTSearchController.h"
#import "YTTheme.h"
#import "YTApi.h"
#import "YTPlayerController.h"
#import "MeshL10n.h"

@interface YTSearchController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@end

@implementation YTSearchController {
    UITextField *_search;
    UITableView *_table;
    UILabel *_hint;
    UIActivityIndicatorView *_spin;
    NSArray *_results;
    NSCache *_imgs;
}

- (void)loadView {
    self.view=[[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.view.backgroundColor=[YTTheme bg];
    _imgs=[[NSCache alloc] init]; _imgs.countLimit=80;
    _imgs.totalCostLimit=8*1024*1024;   // Kosten = dekodierte Pixel-Bytes (256 MB RAM!)
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(memWarn) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    CGFloat W=self.view.bounds.size.width, H=self.view.bounds.size.height;

    // --- Kopfzeile: YouTube-Logo ---
    UIView *top=[[UIView alloc] initWithFrame:CGRectMake(0,0,W,52)]; top.backgroundColor=[YTTheme bar];
    top.autoresizingMask=UIViewAutoresizingFlexibleWidth; [self.view addSubview:top];
    UIImageView *logo=[[UIImageView alloc] initWithImage:[YTTheme logo:22]]; logo.frame=CGRectMake(14,25,22,22); [top addSubview:logo];
    UILabel *wm=[[UILabel alloc] initWithFrame:CGRectMake(42,24,160,24)]; wm.text=@"Tube"; wm.textColor=[YTTheme ink]; wm.font=[UIFont boldSystemFontOfSize:19]; [top addSubview:wm];

    // --- Suchfeld ---
    _search=[[UITextField alloc] initWithFrame:CGRectMake(12,58,W-24,36)];
    _search.backgroundColor=[YTTheme card]; _search.textColor=[YTTheme ink];   // kein tintColor: iOS7+ -> Crash auf iOS6
    _search.layer.cornerRadius=18; _search.font=[UIFont systemFontOfSize:15];
    _search.placeholder=L(@"Search YouTube");   // kein attributedPlaceholder: NSForegroundColorAttributeName ist auf iOS6 nil -> Crash
    UIView *pad=[[UIView alloc] initWithFrame:CGRectMake(0,0,14,10)]; _search.leftView=pad; _search.leftViewMode=UITextFieldViewModeAlways;
    _search.returnKeyType=UIReturnKeySearch; _search.delegate=self; _search.clearButtonMode=UITextFieldViewModeWhileEditing;
    _search.autocorrectionType=UITextAutocorrectionTypeNo; _search.autocapitalizationType=UITextAutocapitalizationTypeNone;
    _search.contentVerticalAlignment=UIControlContentVerticalAlignmentCenter;   // Text sonst zu weit oben (iOS6)
    _search.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:_search];

    _table=[[UITableView alloc] initWithFrame:CGRectMake(0,102,W,H-102) style:UITableViewStylePlain];
    _table.dataSource=self; _table.delegate=self; _table.backgroundColor=[YTTheme bg];
    _table.separatorStyle=UITableViewCellSeparatorStyleNone; _table.rowHeight=[self cardHeight];
    _table.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_table];

    _hint=[[UILabel alloc] initWithFrame:CGRectMake(20,160,W-40,40)]; _hint.text=L(@"Search for videos or music.");
    _hint.textColor=[YTTheme muted]; _hint.font=[UIFont systemFontOfSize:14]; _hint.textAlignment=NSTextAlignmentCenter;
    _hint.autoresizingMask=UIViewAutoresizingFlexibleWidth; [self.view addSubview:_hint];
    _spin=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    _spin.center=CGPointMake(W/2,160); _spin.hidesWhenStopped=YES; [self.view addSubview:_spin];
}

- (void)viewDidLoad { [super viewDidLoad]; [self loadHome]; }
- (void)loadHome {
    // Startseite = „Beliebt"-Feed über die Suche (Browse-Endpoint liefert nichts mehr). Zufällig -> wirkt frisch.
    NSArray *qs=@[@"trending 2025 deutschland", @"neue musik 2025", @"viral 2025", @"gaming highlights 2025", @"lustige videos 2025"];
    NSString *q=qs[arc4random_uniform((uint32_t)qs.count)];
    _hint.hidden=YES; [_spin startAnimating];
    [YTApi search:q completion:^(NSArray *r){
        [_spin stopAnimating];
        if(r.count){ _results=r; [_table reloadData]; }
        else { _hint.hidden=NO; _hint.text=L(@"Search for videos or music."); }
    }];
}
- (CGFloat)thumbH { return (self.view.bounds.size.width-24)*9.0/16.0; }
- (CGFloat)cardHeight { return [self thumbH]+66; }

- (BOOL)textFieldShouldReturn:(UITextField *)tf {
    [tf resignFirstResponder];
    NSString *q=tf.text; if(!q.length) return YES;
    _hint.hidden=YES; _results=nil; [_table reloadData]; [_spin startAnimating];
    [YTApi search:q completion:^(NSArray *r){
        [_spin stopAnimating];
        _results=r; _hint.hidden=(r.count>0); if(!r.count){ _hint.hidden=NO; _hint.text=L(@"Nothing found."); }
        [_table reloadData];
    }];
    return YES;
}
- (void)scrollViewWillBeginDragging:(UIScrollView *)s { [_search resignFirstResponder]; }

- (void)memWarn { [_imgs removeAllObjects]; }
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

// Dekodiert im Hintergrund und verkleinert auf die Pixelgröße der Anzeige (AspectFill-Maß, nie vergrößert).
// Sieht in der Zelle gleich aus, belegt aber nur so viel RAM wie wirklich angezeigt wird.
static UIImage *ytFitImage(UIImage *im, CGSize box, CGFloat scale){
    CGSize s=im.size; if(s.width<=0||s.height<=0||box.width<=0||box.height<=0) return im;
    CGFloat f=MAX(box.width/s.width, box.height/s.height);
    if(f*scale>im.scale) f=im.scale/scale;   // nicht hochskalieren
    CGSize t=CGSizeMake(ceil(s.width*f*scale)/scale, ceil(s.height*f*scale)/scale);
    UIGraphicsBeginImageContextWithOptions(t,NO,scale);
    CGContextSetInterpolationQuality(UIGraphicsGetCurrentContext(),kCGInterpolationHigh);
    [im drawInRect:CGRectMake(0,0,t.width,t.height)];   // erzwingt das Dekodieren hier, nicht beim Scrollen
    UIImage *o=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
    return o?:im;
}

- (void)loadImage:(NSString *)url into:(UIImageView *)iv tv:(UITableView *)tv ip:(NSIndexPath *)ip tag:(int)tag {
    if(!url.length){ iv.image=nil; return; }
    UIImage *c=[_imgs objectForKey:url]; if(c){ iv.image=c; return; }
    iv.image=nil;
    CGSize box=iv.bounds.size; CGFloat scale=[UIScreen mainScreen].scale; NSCache *cache=_imgs;
    dispatch_async(dispatch_get_global_queue(0,0), ^{ UIImage *im=nil;
        @autoreleasepool { NSData *d=[NSData dataWithContentsOfURL:[NSURL URLWithString:url]]; UIImage *raw=d?[UIImage imageWithData:d]:nil; if(raw) im=ytFitImage(raw,box,scale); }
        if(im){ CGImageRef cg=im.CGImage; NSUInteger cost=cg?CGImageGetBytesPerRow(cg)*CGImageGetHeight(cg):0;
            [cache setObject:im forKey:url cost:cost]; dispatch_async(dispatch_get_main_queue(), ^{ UITableViewCell *cc=[tv cellForRowAtIndexPath:ip]; if(cc)((UIImageView*)[cc.contentView viewWithTag:tag]).image=im; }); } });
}

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return _results.count; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    CGFloat W=tv.bounds.size.width, th=[self thumbH], tb=8+th;
    UITableViewCell *c=[tv dequeueReusableCellWithIdentifier:@"r"];
    if(!c){ c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"r"];
        c.backgroundColor=[YTTheme bg]; c.selectionStyle=UITableViewCellSelectionStyleNone;
        UIImageView *thumb=[[UIImageView alloc] initWithFrame:CGRectMake(12,8,W-24,th)]; thumb.tag=1; thumb.backgroundColor=[YTTheme card]; thumb.contentMode=UIViewContentModeScaleAspectFill; thumb.clipsToBounds=YES; thumb.layer.cornerRadius=8; [c.contentView addSubview:thumb];
        UILabel *dur=[[UILabel alloc] initWithFrame:CGRectMake(W-12-46,8+th-22,42,16)]; dur.tag=6; dur.backgroundColor=[UIColor colorWithWhite:0 alpha:0.8]; dur.textColor=[UIColor whiteColor]; dur.font=[UIFont boldSystemFontOfSize:11]; dur.textAlignment=NSTextAlignmentCenter; dur.layer.cornerRadius=3; dur.clipsToBounds=YES; [c.contentView addSubview:dur];
        UIImageView *av=[[UIImageView alloc] initWithFrame:CGRectMake(12,tb+10,36,36)]; av.tag=4; av.backgroundColor=[YTTheme card]; av.contentMode=UIViewContentModeScaleAspectFill; av.clipsToBounds=YES; av.layer.cornerRadius=18; [c.contentView addSubview:av];
        UILabel *ti=[[UILabel alloc] initWithFrame:CGRectMake(58,tb+8,W-58-14,36)]; ti.tag=2; ti.numberOfLines=2; ti.font=[UIFont boldSystemFontOfSize:14]; ti.textColor=[YTTheme ink]; [c.contentView addSubview:ti];
        UILabel *me=[[UILabel alloc] initWithFrame:CGRectMake(58,tb+45,W-58-14,15)]; me.tag=3; me.font=[UIFont systemFontOfSize:11.5]; me.textColor=[YTTheme muted]; [c.contentView addSubview:me];
    }
    NSDictionary *v=_results[ip.row];
    ((UILabel*)[c.contentView viewWithTag:2]).text=v[@"title"];
    UILabel *dur=(UILabel*)[c.contentView viewWithTag:6]; dur.text=[NSString stringWithFormat:@" %@ ",v[@"length"]]; dur.hidden=(![v[@"length"] length]);
    NSMutableArray *parts=[NSMutableArray array];
    if([v[@"author"] length]) [parts addObject:v[@"author"]];
    if([v[@"views"] length]) [parts addObject:v[@"views"]];
    if([v[@"published"] length]) [parts addObject:v[@"published"]];
    ((UILabel*)[c.contentView viewWithTag:3]).text=[parts componentsJoinedByString:@" · "];
    [self loadImage:v[@"thumb"] into:(UIImageView*)[c.contentView viewWithTag:1] tv:tv ip:ip tag:1];
    [self loadImage:v[@"avatar"] into:(UIImageView*)[c.contentView viewWithTag:4] tv:tv ip:ip tag:4];
    return c;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    NSDictionary *v=_results[ip.row];
    YTPlayerController *p=[[YTPlayerController alloc] initWithVideoId:v[@"id"] title:v[@"title"] author:v[@"author"] avatar:v[@"avatar"]];
    [self.navigationController pushViewController:p animated:YES];
}
- (NSUInteger)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }
- (BOOL)shouldAutorotate { return NO; }
@end
