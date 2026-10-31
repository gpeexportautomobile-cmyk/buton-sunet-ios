#import "BRUI.h"
#import "BRLlama.h"

static NSString *BRGrounding(BRCharacter *character, NSString *question) {
    NSArray<BRVerse *> *verses = [[BRCatalog shared] versesForCharacter:character.cid];
    NSSet *skip = [NSSet setWithObjects:@"care", @"este", @"sunt", @"sint", @"pentru", @"unde", @"cine", @"cum", @"din", @"prin", @"doar", @"ceva", @"mai", @"fost", @"aici", @"spui", nil];
    NSMutableArray<NSString *> *needles = [NSMutableArray array];
    for (NSString *token in BRTokens(question)) {
        if (token.length >= 3 && ![skip containsObject:token]) [needles addObject:token];
    }
    NSMutableArray<NSDictionary *> *ranked = [NSMutableArray array];
    for (BRVerse *verse in verses) {
        NSSet *words = [NSSet setWithArray:BRTokens(verse.text)];
        NSInteger score = 0;
        for (NSString *needle in needles) if ([words containsObject:needle]) score++;
        [ranked addObject:@{@"verse": verse, @"score": @(score)}];
    }
    [ranked sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"score"] compare:a[@"score"]];
    }];
    NSMutableArray<BRVerse *> *chosen = [NSMutableArray array];
    if (verses.firstObject) [chosen addObject:verses.firstObject];
    if (verses.count > 1) [chosen addObject:verses[1]];
    for (NSDictionary *row in ranked) {
        if ([row[@"score"] integerValue] <= 0) continue;
        BRVerse *verse = row[@"verse"];
        if (![chosen containsObject:verse]) [chosen addObject:verse];
        if (chosen.count >= 6) break;
    }
    for (BRVerse *verse in verses) {
        if (chosen.count >= 4) break;
        if (![chosen containsObject:verse]) [chosen addObject:verse];
    }
    NSMutableString *block = [NSMutableString string];
    for (BRVerse *verse in chosen) {
        NSString *line = [NSString stringWithFormat:@"%@: %@\n", verse.reference, verse.text];
        if (block.length + line.length > 3200) break;
        [block appendString:line];
    }
    return block;
}

@interface BRBubbleCell : UITableViewCell
@property (nonatomic, strong) UILabel *bubble;
@property (nonatomic, assign) BOOL mine;
@end

@implementation BRBubbleCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    self.backgroundColor = UIColor.blackColor;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    _bubble = [[UILabel alloc] init];
    _bubble.numberOfLines = 0;
    _bubble.font = [UIFont systemFontOfSize:16];
    [self.contentView addSubview:_bubble];
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat maxW = self.contentView.bounds.size.width * 0.78;
    CGSize size = [self.bubble sizeThatFits:CGSizeMake(maxW - 24, 2000)];
    CGFloat w = MIN(maxW, size.width + 24);
    CGFloat x = self.mine ? self.contentView.bounds.size.width - w - 12 : 12;
    self.bubble.frame = CGRectMake(x, 6, w, MAX(36, size.height + 16));
    self.bubble.layer.cornerRadius = 14;
    self.bubble.clipsToBounds = YES;
}
@end

@interface BRChatController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UITextField *input;
@property (nonatomic, strong) UIButton *send;
@property (nonatomic, strong) UIView *bar;
@property (nonatomic, strong) UIView *banner;
@property (nonatomic, strong) UILabel *bannerLabel;
@property (nonatomic, strong) UIButton *download;
@property (nonatomic, copy) NSString *live;
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, assign) CGFloat keyboard;
@end

@implementation BRChatController
- (void)viewDidLoad {
    [super viewDidLoad];
    BRCharacter *character = [[BRCatalog shared] characterById:self.characterId];
    self.title = character.name ?: @"Mesaj";
    self.view.backgroundColor = UIColor.blackColor;
    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.table.backgroundColor = UIColor.blackColor;
    self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.table registerClass:BRBubbleCell.class forCellReuseIdentifier:@"b"];
    [self.view addSubview:self.table];
    self.banner = [[UIView alloc] init];
    self.banner.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1];
    self.bannerLabel = [[UILabel alloc] init];
    self.bannerLabel.textColor = [UIColor colorWithWhite:1 alpha:0.86];
    self.bannerLabel.font = [UIFont systemFontOfSize:13];
    self.bannerLabel.numberOfLines = 0;
    self.bannerLabel.text = @"Ca să vorbească în rol, telefonul descarcă o singură dată un model gratuit (Qwen 0.5B, aproximativ 410 MB). Conversația rămâne pe aparat.";
    self.download = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.download setTitle:@"Descarcă modelul" forState:UIControlStateNormal];
    self.download.tintColor = UIColor.blackColor;
    self.download.backgroundColor = BRGold();
    self.download.layer.cornerRadius = 8;
    self.download.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [self.download addTarget:self action:@selector(startDownload) forControlEvents:UIControlEventTouchUpInside];
    [self.banner addSubview:self.bannerLabel];
    [self.banner addSubview:self.download];
    [self.view addSubview:self.banner];
    self.bar = [[UIView alloc] init];
    self.bar.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
    self.input = [[UITextField alloc] init];
    self.input.borderStyle = UITextBorderStyleRoundedRect;
    self.input.backgroundColor = [UIColor colorWithWhite:0.16 alpha:1];
    self.input.textColor = UIColor.whiteColor;
    self.input.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"Scrie o întrebare…" attributes:@{NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.4]}];
    self.input.delegate = self;
    self.input.returnKeyType = UIReturnKeySend;
    self.send = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.send setTitle:@"Trimite" forState:UIControlStateNormal];
    self.send.tintColor = BRGold();
    self.send.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [self.send addTarget:self action:@selector(sendTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.bar addSubview:self.input];
    [self.bar addSubview:self.send];
    [self.view addSubview:self.bar];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboard:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:BRStateDidChange object:nil];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self refresh]; }
- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }
- (NSArray *)messages { return [[BRStore shared] messagesFor:self.characterId]; }
- (void)refresh {
    self.banner.hidden = [BRLlama shared].downloaded;
    [self.view setNeedsLayout];
    [self.table reloadData];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    CGFloat safeBottom = self.keyboard > 0 ? 0 : self.view.safeAreaInsets.bottom;
    CGFloat barH = 56 + safeBottom;
    self.bar.frame = CGRectMake(0, h - self.keyboard - barH, w, barH);
    self.input.frame = CGRectMake(12, 8, w - 108, 40);
    self.send.frame = CGRectMake(w - 92, 8, 80, 40);
    CGFloat bannerH = self.banner.hidden ? 0 : 132;
    self.banner.frame = CGRectMake(0, self.view.safeAreaInsets.top, w, bannerH);
    self.bannerLabel.frame = CGRectMake(16, 8, w - 32, 68);
    self.download.frame = CGRectMake(16, 82, w - 32, 38);
    self.table.frame = CGRectMake(0, self.view.safeAreaInsets.top + bannerH, w, self.bar.frame.origin.y - self.view.safeAreaInsets.top - bannerH);
}
- (void)keyboard:(NSNotification *)note {
    CGRect frame = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect local = [self.view convertRect:frame fromView:nil];
    self.keyboard = MAX(0, CGRectGetMaxY(self.view.bounds) - local.origin.y);
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.messages.count + (self.live.length ? 1 : 0);
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *text = [self textForRow:indexPath.row];
    CGFloat h = [text boundingRectWithSize:CGSizeMake(tableView.bounds.size.width * 0.78 - 24, 2000) options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:16]} context:nil].size.height;
    return h + 32;
}
- (NSString *)textForRow:(NSInteger)row {
    if (row < (NSInteger)self.messages.count) return self.messages[row][@"text"] ?: @"";
    return self.live ?: @"";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    BRBubbleCell *cell = [tableView dequeueReusableCellWithIdentifier:@"b" forIndexPath:indexPath];
    BOOL mine = NO;
    if (indexPath.row < (NSInteger)self.messages.count) mine = [self.messages[indexPath.row][@"role"] isEqualToString:@"user"];
    cell.mine = mine;
    cell.bubble.text = [self textForRow:indexPath.row];
    cell.bubble.textColor = mine ? UIColor.blackColor : UIColor.whiteColor;
    cell.bubble.backgroundColor = mine ? BRGold() : [UIColor colorWithWhite:0.16 alpha:1];
    cell.bubble.textAlignment = NSTextAlignmentLeft;
    return cell;
}
- (BOOL)textFieldShouldReturn:(UITextField *)textField { [self sendTapped]; return YES; }
- (void)alert:(NSString *)text {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Biblia Reels" message:text preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Bine" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)scrollDown {
    NSInteger rows = [self.table numberOfRowsInSection:0];
    if (rows > 0) [self.table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:rows - 1 inSection:0] atScrollPosition:UITableViewScrollPositionBottom animated:YES];
}
- (void)reloadLive {
    [self.table reloadData];
    [self scrollDown];
}
- (void)startDownload {
    if (self.busy) return;
    self.busy = YES;
    __weak typeof(self) weakSelf = self;
    [[BRLlama shared] downloadWithProgress:^(float progress) {
        weakSelf.bannerLabel.text = [NSString stringWithFormat:@"Se descarcă modelul… %.0f%%. Ține aplicația deschisă.", progress * 100];
    } completion:^(NSError *error) {
        weakSelf.busy = NO;
        if (error) [weakSelf alert:error.localizedDescription];
        [weakSelf refresh];
    }];
}
- (void)sendTapped {
    NSString *text = [self.input.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0 || self.busy) return;
    self.input.text = @"";
    [self.input resignFirstResponder];
    [[BRStore shared] addMessageRole:@"user" text:text character:self.characterId];
    if (![BRLlama shared].downloaded) {
        self.busy = YES;
        self.live = @"Se descarcă modelul pe telefon…";
        [self reloadLive];
        __weak typeof(self) weakSelf = self;
        [[BRLlama shared] downloadWithProgress:^(float progress) {
            weakSelf.live = [NSString stringWithFormat:@"Se descarcă modelul… %.0f%%", progress * 100];
            [weakSelf reloadLive];
        } completion:^(NSError *error) {
            if (error) {
                weakSelf.busy = NO;
                weakSelf.live = nil;
                [weakSelf reloadLive];
                [weakSelf alert:error.localizedDescription];
                return;
            }
            [weakSelf generate:text];
        }];
        return;
    }
    [self generate:text];
}
- (void)generate:(NSString *)text {
    BRCharacter *character = [[BRCatalog shared] characterById:self.characterId];
    self.busy = YES;
    self.live = @"Citește versetele…";
    [self reloadLive];
    NSArray *all = [self messages];
    NSArray *history = all.count ? [all subarrayWithRange:NSMakeRange(0, all.count - 1)] : @[];
    if (history.count > 6) history = [history subarrayWithRange:NSMakeRange(history.count - 6, 6)];
    NSString *system = [NSString stringWithFormat:
                        @"Ești %@, personaj din Geneza, traducerea Cornilescu. "
                        "Vorbești la persoana întâi, în limba română, cald și scurt, maximum 4 fraze. "
                        "Te bazezi doar pe versetele de mai jos. Dacă răspunsul nu este în ele, spui: În versetele pe care le am aici nu scrie asta. "
                        "Nu inventa întâmplări, nume sau învățături din alte cărți.\n\nCine ești: %@\n\nVersete:\n%@",
                        character.name ?: @"personajul", character.bio ?: @"", BRGrounding(character, text)];
    __weak typeof(self) weakSelf = self;
    NSString *cid = self.characterId;
    [[BRLlama shared] replySystem:system history:history user:text onPartial:^(NSString *partial) {
        weakSelf.live = partial;
        [weakSelf reloadLive];
    } done:^(NSString *answer, NSError *error) {
        BRChatController *self_ = weakSelf;
        self_.busy = NO;
        self_.live = nil;
        if (answer.length) [[BRStore shared] addMessageRole:@"assistant" text:answer character:cid];
        else if (self_) [self_ alert:error.localizedDescription ?: @"Nu am primit un răspuns."];
        [self_ refresh];
        [self_ scrollDown];
    }];
}
@end
