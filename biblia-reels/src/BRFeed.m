#import "BRUI.h"
#import "BRLlama.h"
#import <AVFoundation/AVFoundation.h>

static UIFont *BRSerif(CGFloat size, BOOL bold) {
    UIFont *font = [UIFont fontWithName:(bold ? @"Georgia-Bold" : @"Georgia") size:size];
    return font ?: (bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size]);
}

@interface BRItem : NSObject
@property (nonatomic, copy) NSString *itemId;
@property (nonatomic, strong) BRVerse *verse;
@property (nonatomic, copy) NSString *caption;
@property (nonatomic, assign) BOOL reflection;
@end
@implementation BRItem
@end

@interface BRReelCell : UICollectionViewCell
@property (nonatomic, weak) id delegate;
@property (nonatomic, copy) NSString *itemId;
@property (nonatomic, strong) BRVerse *verse;
@property (nonatomic, assign) NSInteger itemIndex;
@property (nonatomic, assign) CGFloat topInset;
- (void)showItem:(BRItem *)item;
- (void)refreshChrome;
- (void)setHighlightWord:(NSInteger)index;
- (void)setHighlightRange:(NSRange)range;
- (void)clearHighlight;
@end

@interface BRReelCell ()
@property (nonatomic, strong) UIImageView *photo;
@property (nonatomic, strong) UIView *shade;
@property (nonatomic, strong) UILabel *mark;
@property (nonatomic, strong) UILabel *counter;
@property (nonatomic, strong) UILabel *reference;
@property (nonatomic, strong) UILabel *caption;
@property (nonatomic, strong) UILabel *subtitle;
@property (nonatomic, strong) UIButton *avatar;
@property (nonatomic, strong) UILabel *avatarName;
@property (nonatomic, strong) UIButton *like;
@property (nonatomic, strong) UIButton *comment;
@property (nonatomic, strong) UIButton *save;
@property (nonatomic, strong) UIButton *share;
@property (nonatomic, strong) UILabel *likeCount;
@property (nonatomic, strong) UILabel *commentCount;
@property (nonatomic, strong) UILabel *saveCount;
@property (nonatomic, copy) NSString *spoken;
@property (nonatomic, copy) NSArray<NSValue *> *tokenRanges;
@property (nonatomic, assign) BOOL burning;
@property (nonatomic, assign) BOOL highlightOn;
@property (nonatomic, assign) NSRange highlight;
@end

@implementation BRReelCell
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.contentView.backgroundColor = UIColor.blackColor;
    self.contentView.clipsToBounds = YES;
    _photo = [[UIImageView alloc] init];
    _photo.contentMode = UIViewContentModeScaleAspectFill;
    _photo.userInteractionEnabled = YES;
    _shade = [[UIView alloc] init];
    _shade.userInteractionEnabled = NO;
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.colors = @[(id)[UIColor colorWithWhite:0 alpha:0].CGColor, (id)[UIColor colorWithWhite:0 alpha:0.78].CGColor];
    gradient.frame = CGRectMake(0, 0, 400, 360);
    [_shade.layer addSublayer:gradient];
    _mark = [self label:BRSerif(18, YES) color:UIColor.whiteColor];
    _counter = [self label:[UIFont systemFontOfSize:13 weight:UIFontWeightMedium] color:[UIColor colorWithWhite:1 alpha:0.75]];
    _reference = [self label:[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold] color:BRGold()];
    _caption = [self label:[UIFont italicSystemFontOfSize:15] color:[UIColor colorWithWhite:1 alpha:0.9]];
    _caption.numberOfLines = 3;
    _subtitle = [self label:BRSerif(20, NO) color:UIColor.whiteColor];
    _subtitle.numberOfLines = 0;
    _avatar = [self iconButton:@"person.fill" action:@selector(profile)];
    _avatar.backgroundColor = [UIColor colorWithWhite:1 alpha:0.16];
    _avatar.layer.cornerRadius = 24;
    _avatar.clipsToBounds = YES;
    _avatarName = [self label:[UIFont systemFontOfSize:10 weight:UIFontWeightSemibold] color:UIColor.whiteColor];
    _avatarName.textAlignment = NSTextAlignmentCenter;
    _like = [self iconButton:@"heart" action:@selector(likeTapped)];
    _comment = [self iconButton:@"bubble.right" action:@selector(commentTap)];
    _save = [self iconButton:@"bookmark" action:@selector(saveTap)];
    _share = [self iconButton:@"square.and.arrow.up" action:@selector(shareTap)];
    _likeCount = [self countLabel];
    _commentCount = [self countLabel];
    _saveCount = [self countLabel];
    for (UIView *view in @[ _photo, _shade, _mark, _counter, _reference, _caption, _subtitle, _avatar, _avatarName, _like, _likeCount, _comment, _commentCount, _save, _saveCount, _share ]) {
        [self.contentView addSubview:view];
    }
    UITapGestureRecognizer *single = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggle)];
    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleLike)];
    doubleTap.numberOfTapsRequired = 2;
    [single requireGestureRecognizerToFail:doubleTap];
    [_photo addGestureRecognizer:single];
    [_photo addGestureRecognizer:doubleTap];
    _mark.text = @"Biblia Reels";
    return self;
}
- (UILabel *)label:(UIFont *)font color:(UIColor *)color {
    UILabel *label = [[UILabel alloc] init];
    label.font = font;
    label.textColor = color;
    label.numberOfLines = 1;
    label.layer.shadowColor = UIColor.blackColor.CGColor;
    label.layer.shadowOffset = CGSizeMake(0, 1);
    label.layer.shadowRadius = 3;
    label.layer.shadowOpacity = 0.8;
    return label;
}
- (UILabel *)countLabel {
    UILabel *label = [self label:[UIFont systemFontOfSize:11 weight:UIFontWeightSemibold] color:UIColor.whiteColor];
    label.textAlignment = NSTextAlignmentCenter;
    return label;
}
- (UIButton *)iconButton:(NSString *)symbol action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:26 weight:UIImageSymbolWeightRegular];
    [button setImage:[[UIImage systemImageNamed:symbol] imageByApplyingSymbolConfiguration:cfg] forState:UIControlStateNormal];
    button.tintColor = UIColor.whiteColor;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}
- (void)prepareForReuse {
    [super prepareForReuse];
    self.burning = NO;
    [self.photo.layer removeAllAnimations];
    self.photo.transform = CGAffineTransformIdentity;
    self.itemId = nil;
    [self clearHighlight];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    CGFloat h = self.contentView.bounds.size.height;
    if (w < 2 || h < 2) return;
    self.photo.frame = self.contentView.bounds;
    self.shade.frame = CGRectMake(0, h * 0.42, w, h * 0.58);
    self.shade.layer.sublayers.firstObject.frame = self.shade.bounds;
    CGFloat top = self.topInset > 1 ? self.topInset : 48;
    self.mark.frame = CGRectMake(16, top + 6, 180, 26);
    self.counter.frame = CGRectMake(150, top + 8, w - 170, 22);
    self.counter.textAlignment = NSTextAlignmentRight;
    CGFloat railX = w - 68;
    CGFloat y = h - 24;
    self.share.frame = CGRectMake(railX, y - 48, 56, 44);
    y -= 52;
    self.saveCount.frame = CGRectMake(railX, y - 14, 56, 14);
    self.save.frame = CGRectMake(railX, y - 58, 56, 44);
    y -= 70;
    self.commentCount.frame = CGRectMake(railX, y - 14, 56, 14);
    self.comment.frame = CGRectMake(railX, y - 58, 56, 44);
    y -= 70;
    self.likeCount.frame = CGRectMake(railX, y - 14, 56, 14);
    self.like.frame = CGRectMake(railX, y - 58, 56, 44);
    y -= 78;
    self.avatar.frame = CGRectMake(railX + 4, y - 48, 48, 48);
    self.avatarName.frame = CGRectMake(railX - 6, y - 2, 68, 28);
    CGFloat textW = w - 100;
    CGFloat subH = [self.subtitle sizeThatFits:CGSizeMake(textW, 280)].height;
    subH = MIN(280, MAX(24, subH));
    CGFloat bottom = h - 18;
    self.subtitle.frame = CGRectMake(16, bottom - subH, textW, subH);
    self.reference.frame = CGRectMake(16, bottom - subH - 22, textW, 20);
    self.caption.frame = CGRectMake(16, bottom - subH - 64, textW, 40);
    if (!self.burning) {
        self.burning = YES;
        [UIView animateWithDuration:16 delay:0 options:UIViewAnimationOptionAutoreverse | UIViewAnimationOptionRepeat | UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionAllowUserInteraction animations:^{
            self.photo.transform = CGAffineTransformMakeScale(1.12, 1.12);
        } completion:nil];
    }
}
- (void)showItem:(BRItem *)item {
    self.itemId = item.itemId;
    self.verse = item.verse;
    self.spoken = item.verse.text.length ? item.verse.text : (item.caption ?: @"");
    self.tokenRanges = [self rangesIn:self.spoken];
    self.caption.hidden = !(item.reflection && item.verse && item.caption.length);
    self.caption.text = item.caption;
    self.reference.text = item.verse ? item.verse.reference : @"Reflecție";
    [self paintHighlight:NO range:NSMakeRange(0, 0)];
    self.photo.image = [BRArt stillForKey:(item.verse.vid ?: item.itemId) chapter:item.verse.chapter];
    NSString *token = item.itemId;
    NSString *url = item.verse.imageURL;
    if (url.length) {
        [[BRCache shared] fetchURL:url completion:^(NSURL *local, NSError *error) {
            if (![self.itemId isEqualToString:token] || !local) return;
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                UIImage *image = [UIImage imageWithData:[NSData dataWithContentsOfURL:local]];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([self.itemId isEqualToString:token] && image) self.photo.image = image;
                });
            });
        }];
    }
    [self refreshChrome];
    [self setNeedsLayout];
}
- (NSArray<NSValue *> *)rangesIn:(NSString *)text {
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"\\S+" options:0 error:nil];
    NSMutableArray *ranges = [NSMutableArray array];
    [re enumerateMatchesInString:text ?: @"" options:0 range:NSMakeRange(0, text.length) usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
        [ranges addObject:[NSValue valueWithRange:match.range]];
    }];
    return ranges;
}
- (void)refreshChrome {
    BRStore *store = [BRStore shared];
    BOOL liked = [store liked:self.itemId];
    BOOL saved = [store savedItem:self.itemId];
    NSString *heart = liked ? @"heart.fill" : @"heart";
    NSString *mark = saved ? @"bookmark.fill" : @"bookmark";
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:26 weight:UIImageSymbolWeightRegular];
    [self.like setImage:[[UIImage systemImageNamed:heart] imageByApplyingSymbolConfiguration:cfg] forState:UIControlStateNormal];
    [self.save setImage:[[UIImage systemImageNamed:mark] imageByApplyingSymbolConfiguration:cfg] forState:UIControlStateNormal];
    self.like.tintColor = liked ? BRGold() : UIColor.whiteColor;
    self.save.tintColor = saved ? BRGold() : UIColor.whiteColor;
    NSInteger comments = [store commentsFor:self.itemId].count;
    self.likeCount.text = liked ? @"1" : @"";
    self.saveCount.text = saved ? @"1" : @"";
    self.commentCount.text = comments ? [NSString stringWithFormat:@"%ld", (long)comments] : @"";
    self.like.accessibilityLabel = @"Apreciază";
    self.comment.accessibilityLabel = @"Comentează";
    self.save.accessibilityLabel = @"Salvează";
    self.share.accessibilityLabel = @"Distribuie";
    BRCharacter *person = self.verse ? [[BRCatalog shared] primaryCharacterForVerse:self.verse] : nil;
    self.avatarName.text = person.name ?: @"";
    self.avatar.backgroundColor = person ? [person.color colorWithAlphaComponent:0.9] : [UIColor colorWithWhite:1 alpha:0.16];
    NSString *initial = person.name.length ? [person.name substringToIndex:1] : @"B";
    [self.avatar setTitle:initial forState:UIControlStateNormal];
    [self.avatar setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
    self.avatar.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    NSString *token = self.itemId;
    if (person.avatarURL.length) {
        [[BRCache shared] fetchURL:person.avatarURL completion:^(NSURL *local, NSError *error) {
            if (![self.itemId isEqualToString:token] || !local) return;
            UIImage *image = [UIImage imageWithData:[NSData dataWithContentsOfURL:local]];
            if (!image) return;
            [self.avatar setTitle:nil forState:UIControlStateNormal];
            [self.avatar setImage:[image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forState:UIControlStateNormal];
            self.avatar.imageView.contentMode = UIViewContentModeScaleAspectFill;
        }];
    } else {
        [self.avatar setImage:nil forState:UIControlStateNormal];
    }
}
- (void)paintHighlight:(BOOL)on range:(NSRange)range {
    NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
    style.alignment = NSTextAlignmentCenter;
    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:self.spoken ?: @"" attributes:@{
        NSFontAttributeName: BRSerif(20, NO),
        NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.92],
        NSParagraphStyleAttributeName: style
    }];
    if (on && range.location != NSNotFound && NSMaxRange(range) <= text.length && range.length > 0) {
        [text addAttributes:@{
            NSForegroundColorAttributeName: BRGold(),
            NSFontAttributeName: BRSerif(20, YES)
        } range:range];
    }
    self.subtitle.attributedText = text;
}
- (void)setHighlightWord:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.tokenRanges.count) { [self clearHighlight]; return; }
    [self paintHighlight:YES range:[self.tokenRanges[index] rangeValue]];
}
- (void)setHighlightRange:(NSRange)range { [self paintHighlight:YES range:range]; }
- (void)clearHighlight { [self paintHighlight:NO range:NSMakeRange(0, 0)]; }
- (void)likeTapped { [self.delegate performSelector:@selector(reelLike:) withObject:self]; }
- (void)commentTap { [self.delegate performSelector:@selector(reelComment:) withObject:self]; }
- (void)saveTap { [self.delegate performSelector:@selector(reelSave:) withObject:self]; }
- (void)shareTap { [self.delegate performSelector:@selector(reelShare:) withObject:self]; }
- (void)profile { [self.delegate performSelector:@selector(reelProfile:) withObject:self]; }
- (void)toggle { [self.delegate performSelector:@selector(reelToggle:) withObject:self]; }
- (void)doubleLike { [self.delegate performSelector:@selector(reelDoubleLike:) withObject:self]; }
@end

@interface BRFeedController () <UICollectionViewDataSource, UICollectionViewDelegate, AVSpeechSynthesizerDelegate>
@property (nonatomic, strong) UICollectionView *collection;
@property (nonatomic, strong) UIView *bar;
@property (nonatomic, strong) NSArray<BRItem *> *items;
@property (nonatomic, assign) NSInteger playing;
@property (nonatomic, assign) BOOL suppressSpeech;
@property (nonatomic, assign) NSInteger mode;
@property (nonatomic, strong) AVAudioPlayer *player;
@property (nonatomic, strong) AVSpeechSynthesizer *synth;
@property (nonatomic, strong) AVSpeechUtterance *utterance;
@property (nonatomic, copy) NSArray *words;
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic, assign) CGSize primedSize;
@property (nonatomic, strong) AVSpeechSynthesisVoice *voice;
@end

@implementation BRFeedController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    self.playing = -1;
    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.scrollDirection = UICollectionViewScrollDirectionVertical;
    layout.minimumLineSpacing = 0;
    layout.minimumInteritemSpacing = 0;
    self.collection = [[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:layout];
    self.collection.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.collection.pagingEnabled = YES;
    self.collection.backgroundColor = UIColor.blackColor;
    self.collection.showsVerticalScrollIndicator = NO;
    self.collection.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.collection.dataSource = self;
    self.collection.delegate = self;
    [self.collection registerClass:BRReelCell.class forCellWithReuseIdentifier:@"reel"];
    [self.view addSubview:self.collection];
    self.bar = [[UIView alloc] init];
    self.bar.backgroundColor = BRGold();
    [self.view addSubview:self.bar];
    self.synth = [AVSpeechSynthesizer new];
    self.synth.delegate = self;
    self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
    [self.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    [self rebuild];
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserver:self selector:@selector(catalogChanged) name:BRCatalogDidUpdate object:nil];
    [nc addObserver:self selector:@selector(reelsChanged) name:BRReelsDidChange object:nil];
    [nc addObserver:self selector:@selector(refreshVisible) name:BRStateDidChange object:nil];
    [nc addObserver:self selector:@selector(pausePlayback) name:BRPauseMedia object:nil];
    [nc addObserver:self selector:@selector(resumeIfVisible) name:UIApplicationDidBecomeActiveNotification object:nil];
}
- (void)dealloc {
    [self.link invalidate];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}
- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }
- (void)rebuild {
    NSMutableArray *items = [NSMutableArray array];
    for (BRVerse *verse in [BRCatalog shared].verses) {
        BRItem *item = [BRItem new];
        item.itemId = verse.vid;
        item.verse = verse;
        [items addObject:item];
    }
    for (NSDictionary *reel in [BRStore shared].reels) {
        BRItem *item = [BRItem new];
        item.itemId = reel[@"id"];
        item.verse = [[BRCatalog shared] verseById:reel[@"verseId"]];
        item.caption = [reel[@"reflection"] isKindOfClass:[NSString class]] ? reel[@"reflection"] : @"";
        item.reflection = YES;
        [items addObject:item];
    }
    NSString *keep = (self.playing >= 0 && self.playing < (NSInteger)self.items.count) ? self.items[self.playing].itemId : [BRStore shared].progressVerseId;
    [self pausePlayback];
    self.items = items;
    [self.collection reloadData];
    BOOL covered = self.view.window.rootViewController.presentedViewController != nil;
    if (keep.length && self.view.window && !covered && self.tabBarController.selectedViewController == self && self.collection.bounds.size.height > 2) {
        NSInteger idx = [self indexOf:keep];
        if (idx >= 0) {
            [self.collection scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:idx inSection:0] atScrollPosition:UICollectionViewScrollPositionTop animated:NO];
            [self playIndex:idx];
        }
    }
}
- (NSInteger)indexOf:(NSString *)itemId {
    for (NSInteger i = 0; i < (NSInteger)self.items.count; i++) if ([self.items[i].itemId isEqualToString:itemId]) return i;
    return -1;
}
- (void)catalogChanged { [self rebuild]; [self refreshVisible]; }
- (void)reelsChanged { [self rebuild]; }
- (void)refreshVisible {
    CGFloat top = self.view.safeAreaInsets.top;
    for (BRReelCell *cell in self.collection.visibleCells) {
        cell.topInset = top;
        NSInteger idx = cell.itemIndex;
        if (idx >= 0 && idx < (NSInteger)self.items.count) cell.counter.text = [NSString stringWithFormat:@"%ld / %ld", (long)(idx + 1), (long)self.items.count];
        [cell refreshChrome];
    }
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGSize size = self.collection.bounds.size;
    UICollectionViewFlowLayout *layout = (UICollectionViewFlowLayout *)self.collection.collectionViewLayout;
    if (size.height > 100 && !CGSizeEqualToSize(layout.itemSize, size)) {
        BOOL first = CGSizeEqualToSize(self.primedSize, CGSizeZero);
        self.primedSize = size;
        layout.itemSize = size;
        [layout invalidateLayout];
        if (first) {
            NSString *pid = [BRStore shared].progressVerseId;
            NSInteger idx = pid.length ? [self indexOf:pid] : 0;
            if (idx < 0) idx = 0;
            if (self.items.count) {
                [self.collection scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:idx inSection:0] atScrollPosition:UICollectionViewScrollPositionTop animated:NO];
                [self playIndex:idx];
            }
        }
    }
    [self updateBar];
    [self refreshVisible];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.playing < 0 && self.items.count && self.collection.bounds.size.height > 100) [self playIndex:[self currentIndex]];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self pausePlayback];
}
- (void)resumeIfVisible {
    if (self.view.window && self.playing < 0) [self playIndex:[self currentIndex]];
}
- (NSInteger)currentIndex {
    CGFloat h = self.collection.bounds.size.height;
    if (h < 2 || self.items.count == 0) return 0;
    NSInteger idx = (NSInteger)((self.collection.contentOffset.y / h) + 0.5);
    if (idx < 0) idx = 0;
    if (idx >= (NSInteger)self.items.count) idx = (NSInteger)self.items.count - 1;
    return idx;
}
- (void)updateBar {
    CGFloat h = self.collection.bounds.size.height;
    CGFloat f = 0;
    if (h > 2 && self.items.count) f = MIN(1, MAX(0, (self.collection.contentOffset.y + h) / (h * self.items.count)));
    self.bar.frame = CGRectMake(0, 0, self.view.bounds.size.width * f, 3);
}
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [self updateBar];
    if (scrollView.bounds.size.height < 2) return;
    NSInteger idx = [self currentIndex];
    if (self.view.window) [self playIndex:idx];
}
- (void)openItemId:(NSString *)itemId {
    NSInteger idx = [self indexOf:itemId];
    if (idx < 0 || self.collection.bounds.size.height < 2) return;
    [self.collection scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:idx inSection:0] atScrollPosition:UICollectionViewScrollPositionTop animated:YES];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self playIndex:idx];
    });
}
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section { return self.items.count; }
- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    BRReelCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"reel" forIndexPath:indexPath];
    cell.delegate = self;
    cell.itemIndex = indexPath.item;
    cell.topInset = self.view.safeAreaInsets.top;
    cell.counter.text = [NSString stringWithFormat:@"%ld / %ld", (long)(indexPath.item + 1), (long)self.items.count];
    [cell showItem:self.items[indexPath.item]];
    return cell;
}
- (void)stopQuiet {
    self.suppressSpeech = YES;
    [self.player stop];
    self.player = nil;
    [self.synth stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    self.utterance = nil;
    self.mode = 0;
    self.suppressSpeech = NO;
}
- (void)pausePlayback {
    [self stopQuiet];
    self.playing = -1;
}
- (BRReelCell *)cellAt:(NSInteger)index {
    for (BRReelCell *cell in self.collection.visibleCells) if (cell.itemIndex == index) return cell;
    return nil;
}
- (NSString *)spokenFor:(BRItem *)item {
    if (item.verse.text.length) return item.verse.text;
    return item.caption ?: @"";
}
- (void)playIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.items.count) return;
    if (index == self.playing) return;
    [self stopQuiet];
    self.playing = index;
    BRItem *item = self.items[index];
    [BRStore shared].progressVerseId = item.verse.vid ?: item.itemId;
    [[self cellAt:index] clearHighlight];
    NSString *audio = (!item.reflection || item.verse) ? item.verse.audioURL : @"";
    if (item.verse.text.length && audio.length && !(item.reflection && item.caption.length && !item.verse)) {
        self.words = item.verse.words ?: @[];
        self.mode = 1;
        NSInteger token = index;
        [[BRCache shared] fetchURL:audio completion:^(NSURL *local, NSError *error) {
            if (self.playing != token) return;
            NSError *playError = nil;
            self.player = local ? [[AVAudioPlayer alloc] initWithContentsOfURL:local error:&playError] : nil;
            if (!self.player) { [self speak:item index:token]; return; }
            self.player.numberOfLoops = -1;
            [self.player play];
        }];
    } else {
        [self speak:item index:index];
    }
}
- (AVSpeechSynthesisVoice *)romanian {
    if (self.voice) return self.voice;
    self.voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"ro-RO"];
    if (!self.voice) {
        for (AVSpeechSynthesisVoice *voice in [AVSpeechSynthesisVoice speechVoices]) {
            if ([voice.language hasPrefix:@"ro"]) { self.voice = voice; break; }
        }
    }
    return self.voice;
}
- (void)speak:(BRItem *)item index:(NSInteger)index {
    NSString *text = [self spokenFor:item];
    if (text.length == 0 || self.playing != index) return;
    AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:text];
    utterance.voice = [self romanian];
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92;
    self.utterance = utterance;
    self.mode = 2;
    self.words = @[];
    [self.synth speakUtterance:utterance];
}
- (void)tick {
    if (self.mode != 1 || !self.player.playing) return;
    NSTimeInterval t = self.player.currentTime;
    NSInteger word = -1;
    for (NSInteger i = 0; i < (NSInteger)self.words.count; i++) {
        NSDictionary *row = self.words[i];
        if (![row isKindOfClass:[NSDictionary class]]) continue;
        double start = [row[@"s"] doubleValue];
        double end = [row[@"e"] doubleValue];
        if (t >= start && t < end + 0.04) { word = i; break; }
    }
    [[self cellAt:self.playing] setHighlightWord:word];
}
- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer willSpeakRangeOfSpeechString:(NSRange)characterRange utterance:(AVSpeechUtterance *)utterance {
    if (utterance != self.utterance) return;
    [[self cellAt:self.playing] setHighlightRange:characterRange];
}
- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didFinishSpeechUtterance:(AVSpeechUtterance *)utterance {
    if (self.suppressSpeech || utterance != self.utterance || self.playing < 0 || !self.view.window) return;
    if (self.playing < (NSInteger)self.items.count) [self speak:self.items[self.playing] index:self.playing];
}
- (void)reelToggle:(BRReelCell *)cell {
    if (self.player) {
        if (self.player.playing) [self.player pause]; else [self.player play];
        return;
    }
    if (self.synth.speaking) [self.synth pauseSpeakingAtBoundary:AVSpeechBoundaryWord];
    else if (self.synth.paused) [self.synth continueSpeaking];
    else if (self.playing >= 0 && self.playing < (NSInteger)self.items.count) [self speak:self.items[self.playing] index:self.playing];
}
- (void)reelLike:(BRReelCell *)cell {
    BOOL on = ![[BRStore shared] liked:cell.itemId];
    [[BRStore shared] setLiked:on item:cell.itemId];
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [haptic impactOccurred];
}
- (void)reelDoubleLike:(BRReelCell *)cell {
    [[BRStore shared] setLiked:YES item:cell.itemId];
}
- (void)reelSave:(BRReelCell *)cell {
    BOOL on = ![[BRStore shared] savedItem:cell.itemId];
    [[BRStore shared] setSaved:on item:cell.itemId];
}
- (void)reelComment:(BRReelCell *)cell {
    BRCommentsController *comments = [BRCommentsController new];
    comments.itemId = cell.itemId;
    comments.titleText = cell.verse ? cell.verse.reference : @"Reflecție";
    comments.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:comments animated:YES completion:nil];
}
- (void)reelShare:(BRReelCell *)cell {
    NSString *body = cell.verse.text.length ? cell.verse.text : @"";
    NSString *text = [NSString stringWithFormat:@"%@\n%@\n— Biblia Reels", cell.verse.reference ?: @"Biblia Reels", body];
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[text] applicationActivities:nil];
    activity.popoverPresentationController.sourceView = cell;
    [self presentViewController:activity animated:YES completion:nil];
}
- (void)reelProfile:(BRReelCell *)cell {
    BRCharacter *person = [[BRCatalog shared] primaryCharacterForVerse:cell.verse];
    if (!person) return;
    BRCharacterController *profile = [BRCharacterController new];
    profile.characterId = person.cid;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:profile];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    BRApplyNavStyle(nav);
    [self presentViewController:nav animated:YES completion:nil];
}
@end
