#import "BRUI.h"
#import "BRLlama.h"
#import <math.h>

void BRApplyNavStyle(UINavigationController *nav) {
    UINavigationBarAppearance *look = [UINavigationBarAppearance new];
    [look configureWithOpaqueBackground];
    look.backgroundColor = UIColor.blackColor;
    look.titleTextAttributes = @{NSForegroundColorAttributeName: UIColor.whiteColor};
    nav.navigationBar.standardAppearance = look;
    nav.navigationBar.scrollEdgeAppearance = look;
    nav.navigationBar.tintColor = BRGold();
    nav.navigationBar.barStyle = UIBarStyleBlack;
}

void BROpenItemFrom(UIViewController *from, NSString *itemId) {
    void (^go)(void) = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:BROpenItem object:nil userInfo:@{@"id": itemId ?: @""}];
    };
    UIViewController *root = from.view.window.rootViewController;
    if (root.presentedViewController) [root dismissViewControllerAnimated:YES completion:go];
    else {
        [from.navigationController popToRootViewControllerAnimated:NO];
        go();
    }
}

static void BRAsk(UIViewController *host, NSString *title, NSString *value, void (^done)(NSString *text)) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = value;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Anulează" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Salvează" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        done(alert.textFields.firstObject.text ?: @"");
    }]];
    [host presentViewController:alert animated:YES completion:nil];
}

static UITableViewCell *BRDequeue(UITableView *table) {
    UITableViewCell *cell = [table dequeueReusableCellWithIdentifier:@"c"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"c"];
        cell.selectedBackgroundView = [UIView new];
        cell.selectedBackgroundView.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    }
    cell.backgroundColor = UIColor.blackColor;
    cell.textLabel.textColor = UIColor.whiteColor;
    cell.detailTextLabel.textColor = [UIColor colorWithWhite:1 alpha:0.62];
    cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
    cell.detailTextLabel.numberOfLines = 2;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.imageView.image = nil;
    return cell;
}

static void BRStyleTable(UITableView *table) {
    table.backgroundColor = UIColor.blackColor;
    table.separatorColor = [UIColor colorWithWhite:1 alpha:0.08];
    table.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    table.tableFooterView = [UIView new];
}

static UIView *BRDot(UIColor *color, NSString *letter) {
    UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 36, 36)];
    dot.backgroundColor = color;
    dot.layer.cornerRadius = 18;
    UILabel *label = [[UILabel alloc] initWithFrame:dot.bounds];
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont boldSystemFontOfSize:16];
    label.textColor = UIColor.blackColor;
    label.text = letter.length ? [letter substringToIndex:1] : @"?";
    [dot addSubview:label];
    return dot;
}

@interface BRDiscoverController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UISearchBar *search;
@property (nonatomic, copy) NSString *query;
@end

@implementation BRDiscoverController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Descoperă";
    self.view.backgroundColor = UIColor.blackColor;
    self.search = [[UISearchBar alloc] init];
    self.search.placeholder = @"Caută un verset sau un personaj";
    self.search.barStyle = UIBarStyleBlack;
    self.search.searchBarStyle = UISearchBarStyleMinimal;
    self.search.delegate = self;
    self.search.tintColor = BRGold();
    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    BRStyleTable(self.table);
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.tableHeaderView = self.search;
    [self.view addSubview:self.table];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload) name:BRCatalogDidUpdate object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload) name:BRStateDidChange object:nil];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.table.frame = self.view.bounds;
    if (fabs(self.search.bounds.size.width - self.view.bounds.size.width) > 1) {
        self.search.frame = CGRectMake(0, 0, self.view.bounds.size.width, 52);
        self.table.tableHeaderView = self.search;
    }
}
- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }
- (void)reload { [self.table reloadData]; }
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text { self.query = text; [self.table reloadData]; }
- (BOOL)filtering { return [self.query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length > 0; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if ([self filtering]) return section == 0 ? @"Personaje" : @"Versete";
    return section == 0 ? @"Urmărești" : @"Personaje";
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if ([self filtering]) {
        if (section == 0) return [[BRCatalog shared] searchCharacters:self.query].count;
        return [[BRCatalog shared] searchVerses:self.query].count;
    }
    if (section == 0) return MAX(1, [BRStore shared].followedIds.count);
    return [BRCatalog shared].characters.count;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = BRDequeue(tableView);
    if ([self filtering] && indexPath.section == 1) {
        BRVerse *verse = [[BRCatalog shared] searchVerses:self.query][indexPath.row];
        cell.textLabel.text = verse.reference;
        cell.detailTextLabel.text = verse.text;
        return cell;
    }
    if (![self filtering] && indexPath.section == 0 && [BRStore shared].followedIds.count == 0) {
        cell.textLabel.text = @"Încă nu urmărești pe nimeni";
        cell.detailTextLabel.text = @"Deschide un personaj și apasă Urmărește.";
        return cell;
    }
    NSArray<BRCharacter *> *people = [self filtering] ? [[BRCatalog shared] searchCharacters:self.query] : ([self filtering] ? @[] : (indexPath.section == 0 ? [self followed] : [BRCatalog shared].characters));
    if (![self filtering] && indexPath.section == 0) people = [self followed];
    if ([self filtering] && indexPath.section == 0) people = [[BRCatalog shared] searchCharacters:self.query];
    if (![self filtering] && indexPath.section == 1) people = [BRCatalog shared].characters;
    BRCharacter *person = people[indexPath.row];
    cell.textLabel.text = person.name;
    cell.detailTextLabel.text = person.bio;
    cell.accessoryView = BRDot(person.color, person.name);
    return cell;
}
- (NSArray<BRCharacter *> *)followed {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *cid in [BRStore shared].followedIds) {
        BRCharacter *person = [[BRCatalog shared] characterById:cid];
        if (person) [out addObject:person];
    }
    return out;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ([self filtering] && indexPath.section == 1) {
        BRVerse *verse = [[BRCatalog shared] searchVerses:self.query][indexPath.row];
        BROpenItemFrom(self, verse.vid);
        return;
    }
    if (![self filtering] && indexPath.section == 0 && [BRStore shared].followedIds.count == 0) return;
    NSArray<BRCharacter *> *people = nil;
    if ([self filtering]) people = [[BRCatalog shared] searchCharacters:self.query];
    else if (indexPath.section == 0) people = [self followed];
    else people = [BRCatalog shared].characters;
    BRCharacterController *profile = [BRCharacterController new];
    profile.characterId = people[indexPath.row].cid;
    [self.navigationController pushViewController:profile animated:YES];
}
- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    if ([view isKindOfClass:[UITableViewHeaderFooterView class]]) {
        UITableViewHeaderFooterView *header = (UITableViewHeaderFooterView *)view;
        header.textLabel.textColor = BRGold();
        header.contentView.backgroundColor = UIColor.blackColor;
    }
}
@end

@interface BRCreateController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) UISegmentedControl *mode;
@property (nonatomic, strong) UISearchBar *search;
@property (nonatomic, strong) UITextView *reflection;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UIButton *publish;
@property (nonatomic, copy) NSString *query;
@property (nonatomic, copy) NSString *verseId;
@end

@implementation BRCreateController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Creează";
    self.view.backgroundColor = UIColor.blackColor;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(close)];
    self.mode = [[UISegmentedControl alloc] initWithItems:@[@"Din verset", @"Reflecție"]];
    self.mode.selectedSegmentIndex = 0;
    self.mode.selectedSegmentTintColor = BRGold();
    [self.mode addTarget:self action:@selector(switched) forControlEvents:UIControlEventValueChanged];
    self.search = [[UISearchBar alloc] init];
    self.search.placeholder = @"Caută versetul";
    self.search.barStyle = UIBarStyleBlack;
    self.search.searchBarStyle = UISearchBarStyleMinimal;
    self.search.delegate = self;
    self.reflection = [[UITextView alloc] init];
    self.reflection.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1];
    self.reflection.textColor = UIColor.whiteColor;
    self.reflection.font = [UIFont systemFontOfSize:17];
    self.reflection.layer.cornerRadius = 10;
    self.reflection.text = @"";
    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    BRStyleTable(self.table);
    self.table.dataSource = self;
    self.table.delegate = self;
    self.publish = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.publish setTitle:@"Publică" forState:UIControlStateNormal];
    self.publish.backgroundColor = BRGold();
    self.publish.tintColor = UIColor.blackColor;
    self.publish.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    self.publish.layer.cornerRadius = 12;
    [self.publish addTarget:self action:@selector(publishTapped) forControlEvents:UIControlEventTouchUpInside];
    for (UIView *view in @[self.mode, self.search, self.reflection, self.table, self.publish]) [self.view addSubview:view];
}
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }
- (void)switched { [self.view setNeedsLayout]; [self.table reloadData]; }
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text { self.query = text; [self.table reloadData]; }
- (NSArray<BRVerse *> *)rows {
    NSString *q = [self.query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (q.length == 0) return [BRCatalog shared].verses;
    return [[BRCatalog shared] searchVerses:q];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width;
    CGFloat top = self.view.safeAreaInsets.top + 12;
    BOOL verseMode = self.mode.selectedSegmentIndex == 0;
    self.mode.frame = CGRectMake(16, top, w - 32, 32);
    self.reflection.frame = CGRectMake(16, top + 48, w - 32, verseMode ? 90 : 220);
    self.search.hidden = !verseMode;
    self.table.hidden = !verseMode;
    self.search.frame = CGRectMake(0, CGRectGetMaxY(self.reflection.frame) + 8, w, 44);
    CGFloat tableY = CGRectGetMaxY(self.search.frame);
    self.table.frame = CGRectMake(0, tableY, w, self.view.bounds.size.height - tableY - 80 - self.view.safeAreaInsets.bottom);
    self.publish.frame = CGRectMake(16, self.view.bounds.size.height - 64 - self.view.safeAreaInsets.bottom, w - 32, 48);
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.rows.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = BRDequeue(tableView);
    BRVerse *verse = self.rows[indexPath.row];
    cell.textLabel.text = verse.reference;
    cell.detailTextLabel.text = verse.text;
    cell.accessoryType = [verse.vid isEqualToString:self.verseId] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    self.verseId = self.rows[indexPath.row].vid;
    [tableView reloadData];
}
- (void)publishTapped {
    BOOL verseMode = self.mode.selectedSegmentIndex == 0;
    NSString *text = [self.reflection.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (verseMode && self.verseId.length == 0) return;
    if (!verseMode && text.length == 0) return;
    NSString *rid = [[BRStore shared] addReelForVerse:(verseMode ? self.verseId : @"") reflection:text];
    UIViewController *root = self.view.window.rootViewController;
    [self dismissViewControllerAnimated:YES completion:^{
        [[NSNotificationCenter defaultCenter] postNotificationName:BROpenItem object:nil userInfo:@{@"id": rid ?: @""}];
        (void)root;
    }];
}
@end

@interface BRMessagesController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *table;
@end

@implementation BRMessagesController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Mesaje";
    self.view.backgroundColor = UIColor.blackColor;
    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    BRStyleTable(self.table);
    self.table.dataSource = self;
    self.table.delegate = self;
    [self.view addSubview:self.table];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload) name:BRCatalogDidUpdate object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload) name:BRStateDidChange object:nil];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; self.table.frame = self.view.bounds; }
- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }
- (void)reload { [self.table reloadData]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return [BRCatalog shared].characters.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = BRDequeue(tableView);
    BRCharacter *person = [BRCatalog shared].characters[indexPath.row];
    NSArray *messages = [[BRStore shared] messagesFor:person.cid];
    cell.textLabel.text = person.name;
    cell.detailTextLabel.text = messages.count ? messages.lastObject[@"text"] : @"Începe conversația, pe baza versetelor.";
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.accessoryView = nil;
    cell.imageView.image = nil;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    BRChatController *chat = [BRChatController new];
    chat.characterId = [BRCatalog shared].characters[indexPath.row].cid;
    [self.navigationController pushViewController:chat animated:YES];
}
@end

@interface BRProfileController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UIView *header;
@property (nonatomic, strong) UILabel *name;
@property (nonatomic, strong) UILabel *progressLabel;
@property (nonatomic, strong) UIView *track;
@property (nonatomic, strong) UIView *fill;
@property (nonatomic, strong) UIButton *continueButton;
@end

@implementation BRProfileController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Profil";
    self.view.backgroundColor = UIColor.blackColor;
    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    BRStyleTable(self.table);
    self.table.dataSource = self;
    self.table.delegate = self;
    [self.view addSubview:self.table];
    self.header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 210)];
    UIView *avatar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 72, 72)];
    avatar.tag = 7;
    avatar.backgroundColor = BRGold();
    avatar.layer.cornerRadius = 36;
    UILabel *initial = [[UILabel alloc] initWithFrame:avatar.bounds];
    initial.tag = 8;
    initial.textAlignment = NSTextAlignmentCenter;
    initial.font = [UIFont fontWithName:@"Georgia-Bold" size:28] ?: [UIFont boldSystemFontOfSize:28];
    initial.textColor = UIColor.blackColor;
    [avatar addSubview:initial];
    self.name = [[UILabel alloc] init];
    self.name.textColor = UIColor.whiteColor;
    self.name.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    self.name.userInteractionEnabled = YES;
    [self.name addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(rename)]];
    self.progressLabel = [[UILabel alloc] init];
    self.progressLabel.textColor = [UIColor colorWithWhite:1 alpha:0.7];
    self.progressLabel.font = [UIFont systemFontOfSize:14];
    self.progressLabel.numberOfLines = 2;
    self.track = [[UIView alloc] init];
    self.track.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    self.track.layer.cornerRadius = 3;
    self.fill = [[UIView alloc] init];
    self.fill.backgroundColor = BRGold();
    self.fill.layer.cornerRadius = 3;
    [self.track addSubview:self.fill];
    self.continueButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.continueButton setTitle:@"Continuă lectura" forState:UIControlStateNormal];
    self.continueButton.tintColor = UIColor.blackColor;
    self.continueButton.backgroundColor = BRGold();
    self.continueButton.layer.cornerRadius = 10;
    self.continueButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [self.continueButton addTarget:self action:@selector(continueReading) forControlEvents:UIControlEventTouchUpInside];
    for (UIView *view in @[avatar, self.name, self.progressLabel, self.track, self.continueButton]) [self.header addSubview:view];
    self.table.tableHeaderView = self.header;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload) name:BRStateDidChange object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload) name:BRCatalogDidUpdate object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload) name:BRReelsDidChange object:nil];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.table.frame = self.view.bounds;
    CGFloat w = self.view.bounds.size.width;
    if (w > 2 && fabs(self.header.bounds.size.width - w) > 1) {
        UIView *avatar = [self.header viewWithTag:7];
        avatar.frame = CGRectMake((w - 72) / 2, 8, 72, 72);
        [self.header viewWithTag:8].frame = avatar.bounds;
        self.name.frame = CGRectMake(16, 88, w - 32, 30);
        self.name.textAlignment = NSTextAlignmentCenter;
        self.progressLabel.frame = CGRectMake(24, 122, w - 48, 36);
        self.track.frame = CGRectMake(24, 162, w - 48, 6);
        self.continueButton.frame = CGRectMake(24, 176, w - 48, 40);
        self.header.frame = CGRectMake(0, 0, w, 228);
        self.table.tableHeaderView = self.header;
    }
    [self paintHeader];
}
- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }
- (void)reload { [self paintHeader]; [self.table reloadData]; }
- (void)paintHeader {
    BRStore *store = [BRStore shared];
    self.name.text = store.displayName;
    UILabel *initial = (UILabel *)[self.header viewWithTag:8];
    initial.text = store.displayName.length ? [store.displayName substringToIndex:1] : @"C";
    NSArray<BRVerse *> *verses = [BRCatalog shared].verses;
    NSInteger index = 0;
    for (NSInteger i = 0; i < (NSInteger)verses.count; i++) if ([verses[i].vid isEqualToString:store.progressVerseId]) index = i;
    CGFloat fraction = verses.count ? (CGFloat)(index + (store.progressVerseId.length ? 1 : 0)) / verses.count : 0;
    if (store.progressVerseId.length == 0) fraction = 0;
    self.fill.frame = CGRectMake(0, 0, self.track.bounds.size.width * fraction, 6);
    BRVerse *current = [[BRCatalog shared] verseById:store.progressVerseId] ?: verses.firstObject;
    self.progressLabel.text = verses.count ? [NSString stringWithFormat:@"Progres de citire: %ld din %ld\n%@", (long)(store.progressVerseId.length ? index + 1 : 0), (long)verses.count, current.reference ?: @""] : @"Nu sunt versete încă.";
    self.progressLabel.textAlignment = NSTextAlignmentCenter;
}
- (void)rename {
    BRAsk(self, @"Numele tău", [BRStore shared].displayName, ^(NSString *text) {
        [BRStore shared].displayName = text;
    });
}
- (void)continueReading {
    NSString *vid = [BRStore shared].progressVerseId;
    if (vid.length == 0) vid = [BRCatalog shared].verses.firstObject.vid;
    BROpenItemFrom(self, vid);
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 5; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"Aprecieri", @"Salvate", @"Personaje urmărite", @"Reflecțiile mele", @"Setări"][section];
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 4) return [NSString stringWithFormat:@"%@\nModel: %@", [BRCatalog shared].statusLine, [BRLlama shared].statusText];
    return nil;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return MAX(1, [BRStore shared].likedIds.count);
    if (section == 1) return MAX(1, [BRStore shared].savedIds.count);
    if (section == 2) return MAX(1, [BRStore shared].followedIds.count);
    if (section == 3) return MAX(1, [BRStore shared].reels.count);
    return 4;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = BRDequeue(tableView);
    BRStore *store = [BRStore shared];
    BRCatalog *catalog = [BRCatalog shared];
    if (indexPath.section == 4) {
        NSArray *titles = @[@"Adresa media", @"Reîncarcă catalogul", @"Adresa modelului", @"Șterge modelul descărcat"];
        cell.textLabel.text = titles[indexPath.row];
        if (indexPath.row == 0) cell.detailTextLabel.text = store.assetBaseURL.length ? store.assetBaseURL : @"Nesetată";
        else if (indexPath.row == 2) cell.detailTextLabel.text = [BRLlama shared].statusText;
        else cell.detailTextLabel.text = @"";
        return cell;
    }
    NSArray *ids = indexPath.section == 0 ? store.likedIds : (indexPath.section == 1 ? store.savedIds : store.followedIds);
    if ((indexPath.section < 3 && ids.count == 0) || (indexPath.section == 3 && store.reels.count == 0)) {
        cell.textLabel.text = @"Nimic încă";
        cell.detailTextLabel.text = @"";
        return cell;
    }
    if (indexPath.section == 3) {
        NSDictionary *reel = store.reels[indexPath.row];
        BRVerse *verse = [catalog verseById:reel[@"verseId"]];
        cell.textLabel.text = verse.reference ?: @"Reflecție";
        cell.detailTextLabel.text = [reel[@"reflection"] length] ? reel[@"reflection"] : verse.text;
        return cell;
    }
    if (indexPath.section == 2) {
        BRCharacter *person = [catalog characterById:ids[indexPath.row]];
        cell.textLabel.text = person.name ?: ids[indexPath.row];
        cell.detailTextLabel.text = person.bio;
        return cell;
    }
    BRVerse *verse = [catalog verseById:ids[indexPath.row]];
    cell.textLabel.text = verse.reference ?: ids[indexPath.row];
    cell.detailTextLabel.text = verse.text;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    BRStore *store = [BRStore shared];
    if (indexPath.section == 4) {
        if (indexPath.row == 0) {
            BRAsk(self, @"Adresa media", store.assetBaseURL, ^(NSString *text) {
                store.assetBaseURL = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                [[BRCatalog shared] refreshFromNetwork];
            });
        } else if (indexPath.row == 1) {
            [[BRCatalog shared] refreshFromNetwork];
        } else if (indexPath.row == 2) {
            BRAsk(self, @"Adresa modelului GGUF", store.modelURL, ^(NSString *text) {
                store.modelURL = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                [self reload];
            });
        } else {
            [[BRLlama shared] deleteModel];
            [self reload];
        }
        return;
    }
    if (indexPath.section == 3) {
        if (store.reels.count == 0) return;
        BROpenItemFrom(self, store.reels[indexPath.row][@"id"]);
        return;
    }
    if (indexPath.section == 2) {
        if (store.followedIds.count == 0) return;
        BRCharacterController *profile = [BRCharacterController new];
        profile.characterId = store.followedIds[indexPath.row];
        [self.navigationController pushViewController:profile animated:YES];
        return;
    }
    NSArray *ids = indexPath.section == 0 ? store.likedIds : store.savedIds;
    if (ids.count == 0) return;
    BROpenItemFrom(self, ids[indexPath.row]);
}
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 3 && [BRStore shared].reels.count > 0;
}
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) [[BRStore shared] removeReel:[BRStore shared].reels[indexPath.row][@"id"]];
}
- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    if ([view isKindOfClass:[UITableViewHeaderFooterView class]]) ((UITableViewHeaderFooterView *)view).textLabel.textColor = BRGold();
}
- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
    if ([view isKindOfClass:[UITableViewHeaderFooterView class]]) ((UITableViewHeaderFooterView *)view).textLabel.textColor = [UIColor colorWithWhite:1 alpha:0.55];
}
@end

@interface BRCharacterController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UIView *header;
@property (nonatomic, strong) UIButton *follow;
@end

@implementation BRCharacterController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    BRStyleTable(self.table);
    self.table.dataSource = self;
    self.table.delegate = self;
    [self.view addSubview:self.table];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload) name:BRCatalogDidUpdate object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload) name:BRStateDidChange object:nil];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    BRCharacter *person = [[BRCatalog shared] characterById:self.characterId];
    self.title = person.name;
    if (self.presentingViewController && self.navigationController.viewControllers.firstObject == self) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(close)];
    }
}
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.table.frame = self.view.bounds;
    if (self.view.bounds.size.width > 2 && fabs(self.header.bounds.size.width - self.view.bounds.size.width) > 1) [self buildHeader];
}
- (BRCharacter *)person { return [[BRCatalog shared] characterById:self.characterId]; }
- (void)buildHeader {
    BRCharacter *person = self.person;
    CGFloat w = self.view.bounds.size.width > 2 ? self.view.bounds.size.width : 320;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 360)];
    header.backgroundColor = UIColor.blackColor;
    UIView *avatar = [[UIView alloc] initWithFrame:CGRectMake((w - 88) / 2, 16, 88, 88)];
    avatar.backgroundColor = person.color;
    avatar.layer.cornerRadius = 44;
    UILabel *initial = [[UILabel alloc] initWithFrame:avatar.bounds];
    initial.textAlignment = NSTextAlignmentCenter;
    initial.font = [UIFont fontWithName:@"Georgia-Bold" size:34] ?: [UIFont boldSystemFontOfSize:34];
    initial.text = person.name.length ? [person.name substringToIndex:1] : @"?";
    [avatar addSubview:initial];
    UILabel *bio = [[UILabel alloc] initWithFrame:CGRectMake(20, 116, w - 40, 72)];
    bio.textColor = [UIColor colorWithWhite:1 alpha:0.88];
    bio.font = [UIFont systemFontOfSize:15];
    bio.numberOfLines = 0;
    bio.textAlignment = NSTextAlignmentCenter;
    bio.text = person.bio;
    self.follow = [UIButton buttonWithType:UIButtonTypeSystem];
    self.follow.frame = CGRectMake(20, 196, w - 40, 42);
    self.follow.layer.cornerRadius = 10;
    self.follow.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [self.follow addTarget:self action:@selector(toggleFollow) forControlEvents:UIControlEventTouchUpInside];
    UILabel *stats = [[UILabel alloc] initWithFrame:CGRectMake(20, 246, w - 40, 36)];
    stats.textAlignment = NSTextAlignmentCenter;
    stats.textColor = [UIColor colorWithWhite:1 alpha:0.7];
    stats.font = [UIFont systemFontOfSize:13];
    stats.numberOfLines = 2;
    BOOL on = [[BRStore shared] following:person.cid];
    stats.text = [NSString stringWithFormat:@"%ld urmăritori   ·   %ld urmărește\n%ld versete", (long)(on ? 1 : 0), (long)person.related.count, (long)person.verseIds.count];
    UIScrollView *related = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 290, w, 56)];
    related.showsHorizontalScrollIndicator = NO;
    CGFloat x = 16;
    for (NSString *cid in person.related) {
        BRCharacter *other = [[BRCatalog shared] characterById:cid];
        if (!other) continue;
        UIButton *chip = [UIButton buttonWithType:UIButtonTypeSystem];
        chip.frame = CGRectMake(x, 8, 120, 36);
        [chip setTitle:other.name forState:UIControlStateNormal];
        chip.tintColor = UIColor.blackColor;
        chip.backgroundColor = other.color;
        chip.layer.cornerRadius = 18;
        chip.titleLabel.font = [UIFont boldSystemFontOfSize:13];
        chip.accessibilityIdentifier = cid;
        [chip addTarget:self action:@selector(openRelated:) forControlEvents:UIControlEventTouchUpInside];
        [related addSubview:chip];
        x += 128;
    }
    related.contentSize = CGSizeMake(x, 56);
    for (UIView *view in @[avatar, bio, self.follow, stats, related]) [header addSubview:view];
    [self paintFollow];
    self.header = header;
    self.table.tableHeaderView = header;
}
- (void)paintFollow {
    BOOL on = [[BRStore shared] following:self.characterId];
    [self.follow setTitle:(on ? @"Urmărești" : @"Urmărește") forState:UIControlStateNormal];
    self.follow.backgroundColor = on ? [UIColor colorWithWhite:0.2 alpha:1] : BRGold();
    self.follow.tintColor = on ? UIColor.whiteColor : UIColor.blackColor;
}
- (void)toggleFollow {
    BRStore *store = [BRStore shared];
    [store setFollowing:![store following:self.characterId] character:self.characterId];
    [self buildHeader];
}
- (void)openRelated:(UIButton *)button {
    BRCharacterController *next = [BRCharacterController new];
    next.characterId = button.accessibilityIdentifier;
    [self.navigationController pushViewController:next animated:YES];
}
- (void)reload { [self buildHeader]; [self.table reloadData]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.person.verseIds.count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @"Versete"; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = BRDequeue(tableView);
    BRVerse *verse = [[BRCatalog shared] verseById:self.person.verseIds[indexPath.row]];
    cell.textLabel.text = verse.reference ?: self.person.verseIds[indexPath.row];
    cell.detailTextLabel.text = verse.text;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    BROpenItemFrom(self, self.person.verseIds[indexPath.row]);
}
- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    if ([view isKindOfClass:[UITableViewHeaderFooterView class]]) ((UITableViewHeaderFooterView *)view).textLabel.textColor = BRGold();
}
@end

@interface BRCommentsController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UITextField *input;
@property (nonatomic, strong) UIView *bar;
@property (nonatomic, assign) CGFloat keyboard;
@end

@implementation BRCommentsController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    BRStyleTable(self.table);
    self.table.dataSource = self;
    self.table.delegate = self;
    [self.view addSubview:self.table];
    self.bar = [[UIView alloc] init];
    self.bar.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
    self.input = [[UITextField alloc] init];
    self.input.borderStyle = UITextBorderStyleRoundedRect;
    self.input.backgroundColor = [UIColor colorWithWhite:0.16 alpha:1];
    self.input.textColor = UIColor.whiteColor;
    self.input.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"Scrie un comentariu…" attributes:@{NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.45]}];
    self.input.delegate = self;
    self.input.returnKeyType = UIReturnKeySend;
    UIButton *send = [UIButton buttonWithType:UIButtonTypeSystem];
    send.tag = 3;
    [send setTitle:@"Trimite" forState:UIControlStateNormal];
    send.tintColor = BRGold();
    [send addTarget:self action:@selector(send) forControlEvents:UIControlEventTouchUpInside];
    [self.bar addSubview:self.input];
    [self.bar addSubview:send];
    [self.view addSubview:self.bar];
    UILabel *title = [[UILabel alloc] init];
    title.tag = 4;
    title.text = self.titleText ?: @"Comentarii";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:17];
    title.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:title];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboard:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload) name:BRStateDidChange object:nil];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    [self.view viewWithTag:4].frame = CGRectMake(16, 16, w - 32, 28);
    CGFloat safe = self.keyboard > 0 ? 0 : self.view.safeAreaInsets.bottom;
    CGFloat barH = 56 + safe;
    self.bar.frame = CGRectMake(0, h - self.keyboard - barH, w, barH);
    self.input.frame = CGRectMake(12, 8, w - 108, 40);
    [self.bar viewWithTag:3].frame = CGRectMake(w - 92, 8, 80, 40);
    self.table.frame = CGRectMake(0, 52, w, self.bar.frame.origin.y - 52);
}
- (void)keyboard:(NSNotification *)note {
    CGRect frame = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect local = [self.view convertRect:frame fromView:nil];
    self.keyboard = MAX(0, CGRectGetMaxY(self.view.bounds) - local.origin.y);
    [self.view setNeedsLayout];
}
- (NSArray *)comments { return [[BRStore shared] commentsFor:self.itemId]; }
- (void)reload { [self.table reloadData]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return MAX(1, self.comments.count); }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = BRDequeue(tableView);
    if (self.comments.count == 0) {
        cell.textLabel.text = @"Niciun comentariu";
        cell.detailTextLabel.text = @"Fii primul care scrie.";
        return cell;
    }
    NSDictionary *row = self.comments[indexPath.row];
    cell.textLabel.text = row[@"author"] ?: @"Cititor";
    cell.detailTextLabel.text = row[@"text"];
    return cell;
}
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath { return self.comments.count > 0; }
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) [[BRStore shared] removeCommentAt:indexPath.row item:self.itemId];
}
- (BOOL)textFieldShouldReturn:(UITextField *)textField { [self send]; return YES; }
- (void)send {
    [[BRStore shared] addComment:self.input.text item:self.itemId];
    self.input.text = @"";
}
@end
