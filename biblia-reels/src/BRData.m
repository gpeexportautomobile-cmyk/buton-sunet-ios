#import "BRData.h"
#import <CommonCrypto/CommonDigest.h>

NSString * const BRCatalogDidUpdate = @"BRCatalogDidUpdate";
NSString * const BRStateDidChange = @"BRStateDidChange";
NSString * const BRReelsDidChange = @"BRReelsDidChange";
NSString * const BROpenItem = @"BROpenItem";
NSString * const BRPauseMedia = @"BRPauseMedia";

static NSInteger BRInt(id value) {
    if ([value isKindOfClass:[NSNumber class]]) return [value integerValue];
    if ([value isKindOfClass:[NSString class]]) return [value integerValue];
    return 0;
}

static NSString *BRStr(id value) {
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

static NSArray *BRArr(id value) {
    return [value isKindOfClass:[NSArray class]] ? value : @[];
}

static NSDictionary *BRBundleJSON(NSString *name) {
    NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:@"json"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    id obj = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    return [obj isKindOfClass:[NSDictionary class]] ? obj : @{};
}

NSString *BRNorm(NSString *text) {
    if (text.length == 0) return @"";
    NSMutableString *s = [text.lowercaseString mutableCopy];
    CFStringTransform((__bridge CFMutableStringRef)s, NULL, kCFStringTransformStripDiacritics, false);
    return s;
}

NSArray<NSString *> *BRTokens(NSString *text) {
    NSString *n = BRNorm(text);
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    NSMutableString *cur = [NSMutableString string];
    for (NSUInteger i = 0; i < n.length; i++) {
        unichar c = [n characterAtIndex:i];
        if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')) {
            [cur appendFormat:@"%C", c];
        } else if (cur.length) {
            [out addObject:[cur copy]];
            [cur setString:@""];
        }
    }
    if (cur.length) [out addObject:[cur copy]];
    return out;
}

UIColor *BRGold(void) {
    return [UIColor colorWithRed:0.902 green:0.765 blue:0.416 alpha:1];
}

UIColor *BRHex(NSString *hex) {
    NSString *s = [[hex stringByReplacingOccurrencesOfString:@"#" withString:@""] lowercaseString];
    if (s.length != 6) return BRGold();
    unsigned rgb = 0;
    [[NSScanner scannerWithString:s] scanHexInt:&rgb];
    return [UIColor colorWithRed:((rgb >> 16) & 255) / 255.0
                           green:((rgb >> 8) & 255) / 255.0
                            blue:(rgb & 255) / 255.0
                           alpha:1];
}

static NSString *BRAbsolute(NSString *base, NSString *path, NSString *version) {
    if (path.length == 0) return @"";
    NSString *full = path;
    if (![path hasPrefix:@"http://"] && ![path hasPrefix:@"https://"]) {
        if (base.length == 0) return @"";
        while ([base hasSuffix:@"/"]) base = [base substringToIndex:base.length - 1];
        while ([path hasPrefix:@"/"]) path = [path substringFromIndex:1];
        full = [NSString stringWithFormat:@"%@/%@", base, path];
    }
    if (version.length && [full rangeOfString:@"?"].location == NSNotFound) {
        NSString *ev = [version stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
        full = [full stringByAppendingFormat:@"?v=%@", ev ?: version];
    }
    return full;
}

static BOOL BRAliasHits(NSArray<NSString *> *aliases, NSArray<NSString *> *toks) {
    NSArray<NSString *> *sorted = [aliases sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSUInteger na = BRTokens(a).count, nb = BRTokens(b).count;
        if (na == nb) return NSOrderedSame;
        return na > nb ? NSOrderedAscending : NSOrderedDescending;
    }];
    for (NSString *alias in sorted) {
        NSArray<NSString *> *need = BRTokens(alias);
        if (need.count == 0 || need.count > toks.count) continue;
        for (NSUInteger i = 0; i + need.count <= toks.count; i++) {
            BOOL ok = YES;
            for (NSUInteger k = 0; k < need.count; k++) {
                if (![toks[i + k] isEqualToString:need[k]]) { ok = NO; break; }
            }
            if (ok) return YES;
        }
    }
    return NO;
}

@implementation BRVerse
- (NSString *)reference {
    if (self.bookName.length == 0) return self.vid ?: @"";
    return [NSString stringWithFormat:@"%@ %ld:%ld", self.bookName, (long)self.chapter, (long)self.number];
}
@end

@interface BRCharacter ()
@property (nonatomic, strong) NSMutableSet<NSString *> *seen;
- (void)resetVerses;
@end

@implementation BRCharacter
- (instancetype)init {
    self = [super init];
    if (self) {
        _verseIds = [NSMutableArray array];
        _aliases = @[];
        _related = @[];
        _bio = @"";
        _colorHex = @"#E6C36A";
        _seen = [NSMutableSet set];
    }
    return self;
}
- (void)resetVerses {
    [self.verseIds removeAllObjects];
    [self.seen removeAllObjects];
}
- (void)addVerseId:(NSString *)vid {
    if (vid.length == 0 || [_seen containsObject:vid]) return;
    [_seen addObject:vid];
    [_verseIds addObject:vid];
}
- (BOOL)hasVerseId:(NSString *)vid {
    return [_seen containsObject:vid ?: @""];
}
- (UIColor *)color { return BRHex(self.colorHex); }
@end

@implementation BRArt
+ (UIImage *)stillForKey:(NSString *)key chapter:(NSInteger)chapter {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; cache.countLimit = 48; });
    NSString *cacheKey = key.length ? key : @"x";
    UIImage *hit = [cache objectForKey:cacheKey];
    if (hit) return hit;
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat new];
    fmt.scale = 1;
    fmt.opaque = YES;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(360, 640) format:fmt];
    unsigned hash = 2166136261u;
    for (NSUInteger i = 0; i < cacheKey.length; i++) hash = (hash ^ [cacheKey characterAtIndex:i]) * 16777619u;
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextRef c = ctx.CGContext;
        UIColor *top = [UIColor colorWithRed:0.04 green:0.08 blue:0.14 alpha:1];
        UIColor *bottom = BRGold();
        if (chapter == 2) {
            top = [UIColor colorWithRed:0.06 green:0.14 blue:0.09 alpha:1];
            bottom = [UIColor colorWithRed:0.56 green:0.75 blue:0.48 alpha:1];
        } else if (chapter == 3) {
            top = [UIColor colorWithRed:0.10 green:0.06 blue:0.12 alpha:1];
            bottom = [UIColor colorWithRed:0.55 green:0.23 blue:0.23 alpha:1];
        } else if (chapter != 1) {
            top = [UIColor colorWithRed:((hash >> 16) & 31) / 255.0 green:((hash >> 8) & 31) / 255.0 blue:((hash) & 31) / 255.0 alpha:1];
            bottom = BRHex([NSString stringWithFormat:@"#%06x", hash & 0xFFFFFF]);
        }
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGGradientRef gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)@[(id)top.CGColor, (id)bottom.CGColor], NULL);
        CGContextDrawLinearGradient(c, gradient, CGPointMake(0, 0), CGPointMake(0, 640), 0);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);
        [[UIColor colorWithWhite:1 alpha:0.28] setStroke];
        UIBezierPath *path = [UIBezierPath bezierPath];
        path.lineWidth = 3;
        if (chapter == 3) {
            [path moveToPoint:CGPointMake(40, 420)];
            for (CGFloat x = 40; x <= 320; x += 8) {
                CGFloat y = 420 + sin((x / 28.0) + (hash % 7)) * 36;
                [path addLineToPoint:CGPointMake(x, y)];
            }
        } else if (chapter == 2) {
            [path addArcWithCenter:CGPointMake(180, 250) radius:90 startAngle:3.4 endAngle:6.0 clockwise:YES];
            [path moveToPoint:CGPointMake(70, 470)];
            [path addQuadCurveToPoint:CGPointMake(290, 470) controlPoint:CGPointMake(180, 360)];
        } else {
            [path addArcWithCenter:CGPointMake(180, 210) radius:70 startAngle:0 endAngle:6.283 clockwise:YES];
        }
        [path stroke];
    }];
    if (image) [cache setObject:image forKey:cacheKey];
    return image;
}
@end

@implementation BRCache
+ (instancetype)shared {
    static BRCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [BRCache new]; });
    return cache;
}
- (NSURL *)root {
    NSString *base = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dir = [base stringByAppendingPathComponent:@"biblia-reels/media"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [NSURL fileURLWithPath:dir];
}
- (NSURL *)fileForURL:(NSString *)url {
    unsigned char md[CC_SHA256_DIGEST_LENGTH];
    NSData *data = [url dataUsingEncoding:NSUTF8StringEncoding];
    CC_SHA256(data.bytes, (CC_LONG)data.length, md);
    NSMutableString *hex = [NSMutableString string];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", md[i]];
    NSString *ext = [NSURL URLWithString:url].pathExtension.lowercaseString;
    if (ext.length == 0 || ext.length > 5) ext = @"bin";
    return [[self root] URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", hex, ext]];
}
- (void)fetchURL:(NSString *)url completion:(void (^)(NSURL *, NSError *))completion {
    if (url.length == 0) {
        completion(nil, [NSError errorWithDomain:@"BibliaReels" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Fără adresă."}]);
        return;
    }
    NSURL *dest = [self fileForURL:url];
    if ([[NSFileManager defaultManager] fileExistsAtPath:dest.path]) {
        completion(dest, nil);
        return;
    }
    NSURL *remote = [NSURL URLWithString:url];
    if (!remote) {
        completion(nil, [NSError errorWithDomain:@"BibliaReels" code:2 userInfo:@{NSLocalizedDescriptionKey: @"URL invalid."}]);
        return;
    }
    [[[NSURLSession sharedSession] downloadTaskWithURL:remote completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        NSInteger status = 200;
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) status = [(NSHTTPURLResponse *)response statusCode];
        if (error || !location || status >= 400) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); });
            return;
        }
        NSError *moveError = nil;
        [[NSFileManager defaultManager] removeItemAtURL:dest error:nil];
        [[NSFileManager defaultManager] moveItemAtURL:location toURL:dest error:&moveError];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(moveError ? nil : dest, moveError); });
    }] resume];
}
@end

@interface BRStore ()
@property (nonatomic, strong) NSMutableDictionary *state;
@property (nonatomic, copy) NSString *path;
@end

@implementation BRStore
+ (instancetype)shared {
    static BRStore *store;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ store = [BRStore new]; });
    return store;
}
- (void)load {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    self.path = [docs stringByAppendingPathComponent:@"state.json"];
    NSData *data = [NSData dataWithContentsOfFile:self.path];
    id obj = data ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil] : nil;
    self.state = [obj isKindOfClass:[NSMutableDictionary class]] ? obj : [NSMutableDictionary dictionary];
    NSDictionary *cfg = BRBundleJSON(@"config");
    if (![self.state[@"displayName"] isKindOfClass:[NSString class]]) self.state[@"displayName"] = @"Cititor";
    if (![self.state[@"assetBaseURL"] isKindOfClass:[NSString class]]) self.state[@"assetBaseURL"] = BRStr(cfg[@"assetBaseURL"]);
    if (![self.state[@"modelURL"] isKindOfClass:[NSString class]]) self.state[@"modelURL"] = BRStr(cfg[@"modelURL"]);
    for (NSString *key in @[@"likes", @"saves", @"comments", @"messages"]) {
        if (![self.state[key] isKindOfClass:[NSMutableDictionary class]]) self.state[key] = [NSMutableDictionary dictionary];
    }
    if (![self.state[@"following"] isKindOfClass:[NSMutableArray class]]) self.state[@"following"] = [NSMutableArray array];
    if (![self.state[@"reels"] isKindOfClass:[NSMutableArray class]]) self.state[@"reels"] = [NSMutableArray array];
    if (![self.state[@"progressVerseId"] isKindOfClass:[NSString class]]) self.state[@"progressVerseId"] = @"";
    [self saveQuiet];
}
- (void)saveQuiet {
    NSData *data = [NSJSONSerialization dataWithJSONObject:self.state options:0 error:nil];
    [data writeToFile:self.path atomically:YES];
}
- (void)save {
    [self saveQuiet];
    [[NSNotificationCenter defaultCenter] postNotificationName:BRStateDidChange object:nil];
}
- (NSMutableDictionary *)box:(NSString *)key {
    id value = self.state[key];
    if (![value isKindOfClass:[NSMutableDictionary class]]) {
        value = [value isKindOfClass:[NSDictionary class]] ? [value mutableCopy] : [NSMutableDictionary dictionary];
        self.state[key] = value;
    }
    return value;
}
- (NSString *)displayName { return self.state[@"displayName"]; }
- (void)setDisplayName:(NSString *)displayName {
    self.state[@"displayName"] = displayName.length ? displayName : @"Cititor";
    [self save];
}
- (NSString *)assetBaseURL { return [self.state[@"assetBaseURL"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @""; }
- (void)setAssetBaseURL:(NSString *)assetBaseURL {
    self.state[@"assetBaseURL"] = assetBaseURL ?: @"";
    [self save];
}
- (NSString *)modelURL { return self.state[@"modelURL"] ?: @""; }
- (void)setModelURL:(NSString *)modelURL {
    self.state[@"modelURL"] = modelURL ?: @"";
    [self save];
}
- (NSString *)progressVerseId { return self.state[@"progressVerseId"] ?: @""; }
- (void)setProgressVerseId:(NSString *)progressVerseId {
    if ([self.progressVerseId isEqualToString:progressVerseId ?: @""]) return;
    self.state[@"progressVerseId"] = progressVerseId ?: @"";
    [self save];
}
- (BOOL)liked:(NSString *)itemId { return [[self box:@"likes"][itemId] boolValue]; }
- (void)setLiked:(BOOL)on item:(NSString *)itemId {
    if (itemId.length == 0) return;
    if (on) [self box:@"likes"][itemId] = @YES; else [[self box:@"likes"] removeObjectForKey:itemId];
    [self save];
}
- (BOOL)savedItem:(NSString *)itemId { return [[self box:@"saves"][itemId] boolValue]; }
- (void)setSaved:(BOOL)on item:(NSString *)itemId {
    if (itemId.length == 0) return;
    if (on) [self box:@"saves"][itemId] = @YES; else [[self box:@"saves"] removeObjectForKey:itemId];
    [self save];
}
- (NSArray<NSDictionary *> *)commentsFor:(NSString *)itemId {
    id value = [self box:@"comments"][itemId];
    return [value isKindOfClass:[NSArray class]] ? value : @[];
}
- (void)addComment:(NSString *)text item:(NSString *)itemId {
    NSString *clean = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (clean.length == 0 || itemId.length == 0) return;
    NSMutableArray *list = [[self commentsFor:itemId] mutableCopy];
    [list addObject:@{@"author": self.displayName, @"text": clean, @"at": @(NSDate.date.timeIntervalSince1970)}];
    [self box:@"comments"][itemId] = list;
    [self save];
}
- (void)removeCommentAt:(NSUInteger)index item:(NSString *)itemId {
    NSMutableArray *list = [[self commentsFor:itemId] mutableCopy];
    if (index >= list.count) return;
    [list removeObjectAtIndex:index];
    [self box:@"comments"][itemId] = list;
    [self save];
}
- (BOOL)following:(NSString *)cid { return [self.followedIds containsObject:cid]; }
- (NSArray<NSString *> *)followedIds {
    NSMutableArray *out = [NSMutableArray array];
    for (id value in self.state[@"following"]) if ([value isKindOfClass:[NSString class]]) [out addObject:value];
    return out;
}
- (void)setFollowing:(BOOL)on character:(NSString *)cid {
    if (cid.length == 0) return;
    NSMutableArray *list = [self.followedIds mutableCopy];
    [list removeObject:cid];
    if (on) [list addObject:cid];
    self.state[@"following"] = list;
    [self save];
}
- (NSArray<NSDictionary *> *)messagesFor:(NSString *)cid {
    id value = [self box:@"messages"][cid];
    return [value isKindOfClass:[NSArray class]] ? value : @[];
}
- (void)addMessageRole:(NSString *)role text:(NSString *)text character:(NSString *)cid {
    if (cid.length == 0 || text.length == 0) return;
    NSMutableArray *list = [[self messagesFor:cid] mutableCopy];
    [list addObject:@{@"role": role ?: @"user", @"text": text}];
    if (list.count > 40) [list removeObjectsInRange:NSMakeRange(0, list.count - 40)];
    [self box:@"messages"][cid] = list;
    [self save];
}
- (NSArray<NSDictionary *> *)reels { return self.state[@"reels"] ?: @[]; }
- (NSString *)addReelForVerse:(NSString *)verseId reflection:(NSString *)text {
    NSMutableArray *list = [self.reels mutableCopy];
    NSString *rid = [NSString stringWithFormat:@"user.%lld", (long long)(NSDate.date.timeIntervalSince1970 * 1000)];
    [list addObject:@{@"id": rid, @"verseId": verseId ?: @"", @"reflection": text ?: @"", @"at": @(NSDate.date.timeIntervalSince1970)}];
    self.state[@"reels"] = list;
    [self saveQuiet];
    [[NSNotificationCenter defaultCenter] postNotificationName:BRReelsDidChange object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:BRStateDidChange object:nil];
    return rid;
}
- (void)removeReel:(NSString *)reelId {
    NSMutableArray *list = [NSMutableArray array];
    for (NSDictionary *reel in self.reels) if (![reel[@"id"] isEqualToString:reelId]) [list addObject:reel];
    self.state[@"reels"] = list;
    [self saveQuiet];
    [[NSNotificationCenter defaultCenter] postNotificationName:BRReelsDidChange object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:BRStateDidChange object:nil];
}
- (NSArray<NSString *> *)keysOf:(NSString *)box {
    return [[self box:box].allKeys sortedArrayUsingSelector:@selector(compare:)];
}
- (NSArray<NSString *> *)likedIds { return [self keysOf:@"likes"]; }
- (NSArray<NSString *> *)savedIds { return [self keysOf:@"saves"]; }
@end

@interface BRCatalog ()
@property (nonatomic, strong) NSMutableArray<BRVerse *> *verseList;
@property (nonatomic, strong) NSMutableDictionary<NSString *, BRVerse *> *verseMap;
@property (nonatomic, strong) NSMutableArray<BRCharacter *> *characterList;
@property (nonatomic, strong) NSMutableDictionary<NSString *, BRCharacter *> *characterMap;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *bookOrders;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSArray<NSString *> *> *seedLinks;
@property (nonatomic, strong) NSMutableSet<NSString *> *seedVerseIds;
@property (nonatomic, strong) NSMutableSet<NSString *> *seedCharIds;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSArray *> *manifestLinks;
@property (nonatomic, assign) BOOL didLoad;
@property (nonatomic, assign) BOOL loading;
@end

@implementation BRCatalog
+ (instancetype)shared {
    static BRCatalog *catalog;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ catalog = [BRCatalog new]; });
    return catalog;
}
- (NSArray<BRVerse *> *)verses { return self.verseList ?: @[]; }
- (NSArray<BRCharacter *> *)characters { return self.characterList ?: @[]; }
- (void)loadBundled {
    if (self.didLoad) return;
    self.didLoad = YES;
    self.verseList = [NSMutableArray array];
    self.verseMap = [NSMutableDictionary dictionary];
    self.characterList = [NSMutableArray array];
    self.characterMap = [NSMutableDictionary dictionary];
    self.bookOrders = [NSMutableDictionary dictionary];
    self.seedLinks = [NSMutableDictionary dictionary];
    self.seedVerseIds = [NSMutableSet set];
    self.seedCharIds = [NSMutableSet set];
    self.manifestLinks = [NSMutableDictionary dictionary];
    NSDictionary *bible = BRBundleJSON(@"bible");
    for (NSDictionary *book in BRArr(bible[@"books"])) {
        if (![book isKindOfClass:[NSDictionary class]]) continue;
        NSString *bookId = BRStr(book[@"id"]);
        if (bookId.length == 0) continue;
        self.bookOrders[bookId] = @(BRInt(book[@"order"]));
        NSString *bookName = BRStr(book[@"name"]);
        for (NSDictionary *chapter in BRArr(book[@"chapters"])) {
            if (![chapter isKindOfClass:[NSDictionary class]]) continue;
            NSInteger chapterN = BRInt(chapter[@"n"]);
            for (NSDictionary *row in BRArr(chapter[@"verses"])) {
                if (![row isKindOfClass:[NSDictionary class]]) continue;
                BRVerse *verse = [BRVerse new];
                verse.bookId = bookId;
                verse.bookName = bookName;
                verse.bookOrder = BRInt(book[@"order"]);
                verse.chapter = chapterN;
                verse.number = BRInt(row[@"n"]);
                verse.text = BRStr(row[@"text"]);
                verse.vid = [NSString stringWithFormat:@"%@.%ld.%ld", bookId, (long)chapterN, (long)verse.number];
                verse.words = @[];
                verse.manifestCharacters = @[];
                self.verseMap[verse.vid] = verse;
                [self.verseList addObject:verse];
                [self.seedVerseIds addObject:verse.vid];
            }
        }
    }
    NSDictionary *people = BRBundleJSON(@"characters");
    for (NSDictionary *row in BRArr(people[@"characters"])) {
        if (![row isKindOfClass:[NSDictionary class]]) continue;
        BRCharacter *character = [self characterFromJSON:row];
        if (!character) continue;
        NSMutableArray *ids = [NSMutableArray array];
        for (id vid in BRArr(row[@"verseIds"])) if ([vid isKindOfClass:[NSString class]]) [ids addObject:vid];
        self.seedLinks[character.cid] = ids;
        [self.seedCharIds addObject:character.cid];
        for (NSString *vid in ids) [character addVerseId:vid];
    }
    [self sortAll];
    NSString *cached = [self manifestCachePath];
    NSData *data = [NSData dataWithContentsOfFile:cached];
    id obj = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if ([obj isKindOfClass:[NSDictionary class]]) [self applyManifest:obj];
    [[NSNotificationCenter defaultCenter] postNotificationName:BRCatalogDidUpdate object:nil];
}
- (NSString *)manifestCachePath {
    NSString *base = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dir = [base stringByAppendingPathComponent:@"biblia-reels"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:@"manifest.json"];
}
- (BRCharacter *)characterFromJSON:(NSDictionary *)row {
    NSString *cid = BRStr(row[@"id"]);
    if (cid.length == 0) return nil;
    BRCharacter *character = self.characterMap[cid] ?: [BRCharacter new];
    character.cid = cid;
    if (BRStr(row[@"name"]).length) character.name = BRStr(row[@"name"]);
    if (character.name.length == 0) character.name = cid;
    if (BRStr(row[@"bio"]).length) character.bio = BRStr(row[@"bio"]);
    if (BRStr(row[@"color"]).length) character.colorHex = BRStr(row[@"color"]);
    character.order = BRInt(row[@"order"]);
    NSMutableArray *aliases = [NSMutableArray array];
    for (id alias in BRArr(row[@"aliases"])) if ([alias isKindOfClass:[NSString class]]) [aliases addObject:alias];
    if (aliases.count) character.aliases = aliases;
    NSMutableArray *related = [NSMutableArray array];
    for (id rel in BRArr(row[@"related"])) if ([rel isKindOfClass:[NSString class]]) [related addObject:rel];
    character.related = related;
    if (!self.characterMap[cid]) {
        self.characterMap[cid] = character;
        [self.characterList addObject:character];
    }
    return character;
}
- (void)applyManifest:(NSDictionary *)manifest {
    NSString *base = [BRStore shared].assetBaseURL;
    NSString *updated = BRStr(manifest[@"updated"]);
    self.manifestUpdated = updated;
    self.manifestLinks = [NSMutableDictionary dictionary];
    for (NSDictionary *book in BRArr(manifest[@"books"])) {
        if (![book isKindOfClass:[NSDictionary class]]) continue;
        NSString *bookId = BRStr(book[@"id"]);
        if (bookId.length) self.bookOrders[bookId] = @(BRInt(book[@"order"]));
    }
    for (NSDictionary *row in BRArr(manifest[@"characters"])) {
        if (![row isKindOfClass:[NSDictionary class]]) continue;
        BRCharacter *character = [self characterFromJSON:row];
        if (!character) continue;
        character.avatarURL = BRAbsolute(base, BRStr(row[@"avatar"]), updated);
        NSMutableArray *ids = [NSMutableArray array];
        for (id vid in BRArr(row[@"verseIds"])) if ([vid isKindOfClass:[NSString class]]) [ids addObject:vid];
        if (ids.count) self.manifestLinks[character.cid] = ids;
    }
    for (NSDictionary *row in BRArr(manifest[@"verses"])) {
        if (![row isKindOfClass:[NSDictionary class]]) continue;
        NSString *vid = BRStr(row[@"id"]);
        if (vid.length == 0) continue;
        BRVerse *verse = self.verseMap[vid];
        if (!verse) {
            verse = [BRVerse new];
            verse.vid = vid;
            verse.words = @[];
            self.verseMap[vid] = verse;
            [self.verseList addObject:verse];
        }
        if (BRStr(row[@"text"]).length) verse.text = BRStr(row[@"text"]);
        if (BRStr(row[@"bookId"]).length) verse.bookId = BRStr(row[@"bookId"]);
        if (BRStr(row[@"book"]).length) verse.bookName = BRStr(row[@"book"]);
        if (row[@"chapter"]) verse.chapter = BRInt(row[@"chapter"]);
        if (row[@"verse"]) verse.number = BRInt(row[@"verse"]);
        if (row[@"bookOrder"]) verse.bookOrder = BRInt(row[@"bookOrder"]);
        else if (self.bookOrders[verse.bookId]) verse.bookOrder = self.bookOrders[verse.bookId].integerValue;
        verse.imageURL = BRAbsolute(base, BRStr(row[@"image"]), updated);
        verse.audioURL = BRAbsolute(base, BRStr(row[@"audio"]), updated);
        verse.words = [row[@"words"] isKindOfClass:[NSArray class]] ? row[@"words"] : @[];
        NSMutableArray *mentions = [NSMutableArray array];
        for (id cid in BRArr(row[@"characters"])) if ([cid isKindOfClass:[NSString class]]) [mentions addObject:cid];
        verse.manifestCharacters = mentions;
    }
    [self relink];
    [self sortAll];
}
- (void)relink {
    for (BRCharacter *character in self.characterList) {
        [character resetVerses];
        for (NSString *vid in self.seedLinks[character.cid] ?: @[]) [character addVerseId:vid];
    }
    for (BRVerse *verse in self.verseList) {
        NSArray<NSString *> *toks = BRTokens(verse.text);
        BOOL seedVerse = [self.seedVerseIds containsObject:verse.vid];
        for (BRCharacter *character in self.characterList) {
            if (seedVerse && [self.seedCharIds containsObject:character.cid]) continue;
            if (BRAliasHits(character.aliases, toks)) [character addVerseId:verse.vid];
        }
        for (NSString *cid in verse.manifestCharacters) {
            BRCharacter *character = [self characterById:cid] ?: [self stubCharacter:cid];
            [character addVerseId:verse.vid];
        }
    }
    for (NSString *cid in self.manifestLinks) {
        BRCharacter *character = [self characterById:cid] ?: [self stubCharacter:cid];
        for (NSString *vid in self.manifestLinks[cid]) if ([self verseById:vid]) [character addVerseId:vid];
    }
    for (BRCharacter *character in self.characterList) {
        [character.verseIds sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            return [self compareVid:a with:b];
        }];
    }
}
- (BRCharacter *)stubCharacter:(NSString *)cid {
    BRCharacter *character = [BRCharacter new];
    character.cid = cid;
    character.name = cid;
    character.bio = @"Personaj apărut în catalogul nou.";
    character.order = 90;
    self.characterMap[cid] = character;
    [self.characterList addObject:character];
    return character;
}
- (NSComparisonResult)compareVid:(NSString *)a with:(NSString *)b {
    BRVerse *va = self.verseMap[a];
    BRVerse *vb = self.verseMap[b];
    if (!va || !vb) return [a compare:b];
    if (va.bookOrder != vb.bookOrder) return va.bookOrder < vb.bookOrder ? NSOrderedAscending : NSOrderedDescending;
    if (va.chapter != vb.chapter) return va.chapter < vb.chapter ? NSOrderedAscending : NSOrderedDescending;
    if (va.number != vb.number) return va.number < vb.number ? NSOrderedAscending : NSOrderedDescending;
    return [a compare:b];
}
- (void)sortAll {
    [self.verseList sortUsingComparator:^NSComparisonResult(BRVerse *a, BRVerse *b) {
        return [self compareVid:a.vid with:b.vid];
    }];
    [self.characterList sortUsingComparator:^NSComparisonResult(BRCharacter *a, BRCharacter *b) {
        if (a.order != b.order) return a.order < b.order ? NSOrderedAscending : NSOrderedDescending;
        return [a.name localizedCompare:b.name];
    }];
}
- (void)refreshFromNetwork {
    NSString *base = [BRStore shared].assetBaseURL;
    if (base.length == 0) {
        self.loading = NO;
        self.lastError = @"";
        [[NSNotificationCenter defaultCenter] postNotificationName:BRCatalogDidUpdate object:nil];
        return;
    }
    NSURL *baseURL = [NSURL URLWithString:base];
    if (!baseURL.scheme || !([baseURL.scheme isEqualToString:@"http"] || [baseURL.scheme isEqualToString:@"https"])) {
        self.lastError = @"Adresa media trebuie să înceapă cu http:// sau https://.";
        [[NSNotificationCenter defaultCenter] postNotificationName:BRCatalogDidUpdate object:nil];
        return;
    }
    NSString *full = BRAbsolute(base, @"manifest.json", nil);
    NSString *bust = [full stringByAppendingFormat:@"%@t=%lld", [full containsString:@"?"] ? @"&" : @"?", (long long)NSDate.date.timeIntervalSince1970];
    self.loading = YES;
    self.lastError = @"";
    [[NSNotificationCenter defaultCenter] postNotificationName:BRCatalogDidUpdate object:nil];
    [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:bust] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.loading = NO;
            NSInteger status = 200;
            if ([response isKindOfClass:[NSHTTPURLResponse class]]) status = [(NSHTTPURLResponse *)response statusCode];
            id obj = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            if (error || status >= 400 || ![obj isKindOfClass:[NSDictionary class]] || ![obj[@"verses"] isKindOfClass:[NSArray class]]) {
                self.lastError = @"Nu am putut descărca catalogul. Rămân versetele deja de pe telefon.";
                [[NSNotificationCenter defaultCenter] postNotificationName:BRCatalogDidUpdate object:nil];
                return;
            }
            [data writeToFile:[self manifestCachePath] atomically:YES];
            [self applyManifest:obj];
            self.lastError = @"";
            [[NSNotificationCenter defaultCenter] postNotificationName:BRCatalogDidUpdate object:nil];
        });
    }] resume];
}
- (BRVerse *)verseById:(NSString *)vid { return vid ? self.verseMap[vid] : nil; }
- (BRCharacter *)characterById:(NSString *)cid { return cid ? self.characterMap[cid] : nil; }
- (NSArray<BRVerse *> *)versesForCharacter:(NSString *)cid {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *vid in [self characterById:cid].verseIds) {
        BRVerse *verse = [self verseById:vid];
        if (verse) [out addObject:verse];
    }
    return out;
}
- (NSArray<BRCharacter *> *)charactersMentionedIn:(BRVerse *)verse {
    NSMutableArray *out = [NSMutableArray array];
    for (BRCharacter *character in self.characterList) if ([character hasVerseId:verse.vid]) [out addObject:character];
    return out;
}
- (BRCharacter *)primaryCharacterForVerse:(BRVerse *)verse {
    BRCharacter *best = nil;
    for (BRCharacter *character in [self charactersMentionedIn:verse]) {
        if (!best || character.verseIds.count < best.verseIds.count) best = character;
    }
    return best;
}
- (NSArray<BRVerse *> *)searchVerses:(NSString *)query {
    NSString *n = BRNorm(query);
    if (n.length == 0) return @[];
    NSMutableArray *out = [NSMutableArray array];
    for (BRVerse *verse in self.verseList) {
        if ([BRNorm(verse.text) containsString:n] || [BRNorm(verse.reference) containsString:n] || [verse.vid containsString:n]) {
            [out addObject:verse];
            if (out.count >= 100) break;
        }
    }
    return out;
}
- (NSArray<BRCharacter *> *)searchCharacters:(NSString *)query {
    NSString *n = BRNorm(query);
    if (n.length == 0) return self.characterList;
    NSMutableArray *out = [NSMutableArray array];
    for (BRCharacter *character in self.characterList) {
        if ([BRNorm(character.name) containsString:n] || [BRNorm(character.bio) containsString:n]) [out addObject:character];
    }
    return out;
}
- (NSString *)statusLine {
    if (self.loading) return @"Se actualizează catalogul…";
    if (self.lastError.length) return self.lastError;
    if ([BRStore shared].assetBaseURL.length == 0) return @"Fără adresă media. Versetele folosesc desenul și vocea telefonului.";
    if (self.manifestUpdated.length) return [NSString stringWithFormat:@"Catalog: %@", self.manifestUpdated];
    return @"Catalog local.";
}
@end
