#import <UIKit/UIKit.h>

extern NSString * const BRCatalogDidUpdate;
extern NSString * const BRStateDidChange;
extern NSString * const BRReelsDidChange;
extern NSString * const BROpenItem;
extern NSString * const BRPauseMedia;

NSString *BRNorm(NSString *text);
NSArray<NSString *> *BRTokens(NSString *text);
UIColor *BRGold(void);
UIColor *BRHex(NSString *hex);

@interface BRVerse : NSObject
@property (nonatomic, copy) NSString *vid;
@property (nonatomic, copy) NSString *bookId;
@property (nonatomic, copy) NSString *bookName;
@property (nonatomic, assign) NSInteger bookOrder;
@property (nonatomic, assign) NSInteger chapter;
@property (nonatomic, assign) NSInteger number;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *imageURL;
@property (nonatomic, copy) NSString *audioURL;
@property (nonatomic, copy) NSArray *words;
@property (nonatomic, copy) NSArray<NSString *> *manifestCharacters;
- (NSString *)reference;
@end

@interface BRCharacter : NSObject
@property (nonatomic, copy) NSString *cid;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *bio;
@property (nonatomic, copy) NSString *avatarURL;
@property (nonatomic, copy) NSString *colorHex;
@property (nonatomic, assign) NSInteger order;
@property (nonatomic, copy) NSArray<NSString *> *aliases;
@property (nonatomic, copy) NSArray<NSString *> *related;
@property (nonatomic, strong) NSMutableArray<NSString *> *verseIds;
- (void)addVerseId:(NSString *)vid;
- (BOOL)hasVerseId:(NSString *)vid;
- (UIColor *)color;
@end

@interface BRArt : NSObject
+ (UIImage *)stillForKey:(NSString *)key chapter:(NSInteger)chapter;
@end

@interface BRCache : NSObject
+ (instancetype)shared;
- (NSURL *)fileForURL:(NSString *)url;
- (void)fetchURL:(NSString *)url completion:(void (^)(NSURL *local, NSError *error))completion;
@end

@interface BRStore : NSObject
+ (instancetype)shared;
- (void)load;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *assetBaseURL;
@property (nonatomic, copy) NSString *modelURL;
@property (nonatomic, copy) NSString *progressVerseId;
- (BOOL)liked:(NSString *)itemId;
- (void)setLiked:(BOOL)on item:(NSString *)itemId;
- (BOOL)savedItem:(NSString *)itemId;
- (void)setSaved:(BOOL)on item:(NSString *)itemId;
- (NSArray<NSDictionary *> *)commentsFor:(NSString *)itemId;
- (void)addComment:(NSString *)text item:(NSString *)itemId;
- (void)removeCommentAt:(NSUInteger)index item:(NSString *)itemId;
- (BOOL)following:(NSString *)cid;
- (void)setFollowing:(BOOL)on character:(NSString *)cid;
- (NSArray<NSString *> *)followedIds;
- (NSArray<NSDictionary *> *)messagesFor:(NSString *)cid;
- (void)addMessageRole:(NSString *)role text:(NSString *)text character:(NSString *)cid;
- (NSArray<NSDictionary *> *)reels;
- (NSString *)addReelForVerse:(NSString *)verseId reflection:(NSString *)text;
- (void)removeReel:(NSString *)reelId;
- (NSArray<NSString *> *)likedIds;
- (NSArray<NSString *> *)savedIds;
@end

@interface BRCatalog : NSObject
+ (instancetype)shared;
- (void)loadBundled;
- (void)refreshFromNetwork;
@property (nonatomic, readonly) NSArray<BRVerse *> *verses;
@property (nonatomic, readonly) NSArray<BRCharacter *> *characters;
@property (nonatomic, readonly) BOOL loading;
@property (nonatomic, copy) NSString *lastError;
@property (nonatomic, copy) NSString *manifestUpdated;
- (BRVerse *)verseById:(NSString *)vid;
- (BRCharacter *)characterById:(NSString *)cid;
- (NSArray<BRVerse *> *)versesForCharacter:(NSString *)cid;
- (NSArray<BRCharacter *> *)charactersMentionedIn:(BRVerse *)verse;
- (BRCharacter *)primaryCharacterForVerse:(BRVerse *)verse;
- (NSArray<BRVerse *> *)searchVerses:(NSString *)query;
- (NSArray<BRCharacter *> *)searchCharacters:(NSString *)query;
- (NSString *)statusLine;
@end
