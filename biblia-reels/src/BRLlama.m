#import "BRLlama.h"
#import "BRData.h"
#import "llama_bridge.h"
#import <stdlib.h>

static const unsigned long long BRMinModelBytes = 50ull * 1024ull * 1024ull;

static NSError *BRErr(NSString *text) {
    return [NSError errorWithDomain:@"BibliaReels" code:1 userInfo:@{NSLocalizedDescriptionKey: text ?: @"Eroare"}];
}

@interface BRPartialBox : NSObject
@property (nonatomic, copy) void (^partial)(NSString *text);
@end
@implementation BRPartialBox
@end

static void BRPartialThunk(const char *text, void *user) {
    BRPartialBox *box = (__bridge BRPartialBox *)user;
    if (!box.partial || !text) return;
    NSString *full = [NSString stringWithUTF8String:text];
    if (full.length == 0) return;
    void (^cb)(NSString *) = box.partial;
    dispatch_async(dispatch_get_main_queue(), ^{ cb(full); });
}

static void BRLoadThunk(float progress, void *user) {
    (void)progress;
    (void)user;
}

@interface BRLlama () <NSURLSessionDownloadDelegate>
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSURLSessionDownloadTask *task;
@property (nonatomic, assign) float progress;
@property (nonatomic, assign) BOOL downloading;
@property (nonatomic, assign) BOOL moved;
@property (nonatomic, assign) BOOL cancelRequested;
@property (nonatomic, strong) NSData *resumeData;
@property (nonatomic, strong) NSError *pendingError;
@property (nonatomic, copy) void (^downloadDone)(NSError *error);
@property (nonatomic, copy) void (^progressBlock)(float progress);
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, assign) br_engine *engine;
@end

@implementation BRLlama
+ (instancetype)shared {
    static BRLlama *llama;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ llama = [BRLlama new]; });
    return llama;
}
- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("biblia.reels.llama", DISPATCH_QUEUE_SERIAL);
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.timeoutIntervalForRequest = 60;
        cfg.timeoutIntervalForResource = 60 * 45;
        cfg.HTTPAdditionalHeaders = @{@"User-Agent": @"BibliaReels/1.0"};
        _session = [NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:[NSOperationQueue mainQueue]];
    }
    return self;
}
- (NSURL *)directory {
    NSString *base = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dir = [base stringByAppendingPathComponent:@"BibliaReels/models"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [NSURL fileURLWithPath:dir isDirectory:YES];
}
- (NSString *)remoteURL {
    NSString *url = [BRStore shared].modelURL;
    return url.length ? url : @"";
}
- (NSString *)fileName {
    NSString *name = [NSURL URLWithString:self.remoteURL].lastPathComponent;
    if (name.length < 5) name = @"model.gguf";
    return name;
}
- (NSURL *)fileURL {
    return [[self directory] URLByAppendingPathComponent:self.fileName];
}
- (unsigned long long)fileBytes {
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:self.fileURL.path error:nil];
    return [attrs fileSize];
}
- (BOOL)downloaded {
    return self.fileBytes > BRMinModelBytes;
}
- (NSString *)statusText {
    if (self.downloading) return [NSString stringWithFormat:@"Se descarcă… %.0f%%", self.progress * 100];
    if (self.downloaded) return [NSString stringWithFormat:@"Pe telefon · %.0f MB", self.fileBytes / 1024.0 / 1024.0];
    return @"Nedescărcat · aproximativ 410 MB";
}
- (void)downloadWithProgress:(void (^)(float))progress completion:(void (^)(NSError *))completion {
    if (self.downloaded) {
        if (completion) completion(nil);
        return;
    }
    if (self.downloading) {
        if (completion) completion(BRErr(@"Descărcarea este deja pornită."));
        return;
    }
    NSString *remote = self.remoteURL;
    NSURL *url = [NSURL URLWithString:remote];
    if (!url.scheme) {
        if (completion) completion(BRErr(@"Adresa modelului nu este validă. O poți schimba din Profil."));
        return;
    }
    self.downloadDone = completion;
    self.progressBlock = progress;
    self.downloading = YES;
    self.moved = NO;
    self.pendingError = nil;
    self.cancelRequested = NO;
    self.progress = 0;
    NSURLSessionDownloadTask *task = self.resumeData ? [self.session downloadTaskWithResumeData:self.resumeData] : [self.session downloadTaskWithURL:url];
    self.resumeData = nil;
    self.task = task;
    [task resume];
    if (progress) progress(0);
}
- (void)cancelDownload {
    self.cancelRequested = YES;
    [self.task cancelByProducingResumeData:^(NSData *data) { self.resumeData = data; }];
}
- (void)deleteModel {
    [self cancelDownload];
    [[NSFileManager defaultManager] removeItemAtURL:self.fileURL error:nil];
    dispatch_async(self.queue, ^{
        br_engine_free(self.engine);
        self.engine = NULL;
    });
}
- (void)finishDownload:(NSError *)error {
    self.downloading = NO;
    self.task = nil;
    void (^done)(NSError *) = self.downloadDone;
    self.downloadDone = nil;
    self.progressBlock = nil;
    if (done) done(error);
}
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didWriteData:(int64_t)bytes totalBytesWritten:(int64_t)written totalBytesExpectedToWrite:(int64_t)expected {
    if (expected > 0) self.progress = (float)written / (float)expected;
    else self.progress = 0;
    if (self.progressBlock) self.progressBlock(self.progress);
}
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didFinishDownloadingToURL:(NSURL *)location {
    NSInteger status = 200;
    if ([task.response isKindOfClass:[NSHTTPURLResponse class]]) status = [(NSHTTPURLResponse *)task.response statusCode];
    if (status >= 400) {
        self.pendingError = BRErr(@"Serverul modelului a răspuns cu o eroare. Încearcă din nou.");
        return;
    }
    NSError *move = nil;
    NSURL *dest = self.fileURL;
    [[NSFileManager defaultManager] removeItemAtURL:dest error:nil];
    [[NSFileManager defaultManager] moveItemAtURL:location toURL:dest error:&move];
    [dest setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
    if (move) self.pendingError = move;
    else self.moved = YES;
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (self.cancelRequested) {
        self.cancelRequested = NO;
        [self finishDownload:BRErr(@"Descărcarea a fost oprită.")];
        return;
    }
    if (error) {
        NSData *resume = error.userInfo[NSURLSessionDownloadTaskResumeData];
        if (resume) self.resumeData = resume;
        [self finishDownload:BRErr(@"Descărcarea s-a întrerupt. Apasă din nou; continuă de unde a rămas.")];
        return;
    }
    if (self.pendingError || !self.moved) {
        [[NSFileManager defaultManager] removeItemAtURL:self.fileURL error:nil];
        [self finishDownload:self.pendingError ?: BRErr(@"Nu am putut salva modelul.")];
        return;
    }
    if (self.fileBytes < BRMinModelBytes) {
        [[NSFileManager defaultManager] removeItemAtURL:self.fileURL error:nil];
        [self finishDownload:BRErr(@"Fișierul primit este prea mic. Verifică rețeaua și încearcă din nou.")];
        return;
    }
    self.progress = 1;
    [self finishDownload:nil];
}
- (void)replySystem:(NSString *)system history:(NSArray<NSDictionary *> *)history user:(NSString *)user onPartial:(void (^)(NSString *))partial done:(void (^)(NSString *, NSError *))done {
    if (!self.downloaded) {
        if (done) done(nil, BRErr(@"Modelul nu este descărcat."));
        return;
    }
    NSString *path = self.fileURL.path;
    int threads = (int)MIN(4, MAX(1, (NSInteger)NSProcessInfo.processInfo.processorCount));
    dispatch_async(self.queue, ^{
        char err[512];
        err[0] = 0;
        if (!self.engine) {
            self.engine = br_engine_load(path.UTF8String, 2048, threads, BRLoadThunk, NULL, err, sizeof(err));
            if (!self.engine) {
                NSString *msg = err[0] ? [NSString stringWithUTF8String:err] : @"Modelul nu a putut fi încărcat.";
                dispatch_async(dispatch_get_main_queue(), ^{ if (done) done(nil, BRErr(msg)); });
                return;
            }
        }
        NSMutableArray<NSString *> *roles = [NSMutableArray array];
        NSMutableArray<NSString *> *contents = [NSMutableArray array];
        for (NSDictionary *row in history) {
            NSString *role = [row[@"role"] isKindOfClass:[NSString class]] ? row[@"role"] : @"user";
            NSString *text = [row[@"text"] isKindOfClass:[NSString class]] ? row[@"text"] : @"";
            if (text.length == 0) continue;
            if (![role isEqualToString:@"assistant"] && ![role isEqualToString:@"user"]) role = @"user";
            [roles addObject:role];
            [contents addObject:text];
        }
        const char **cRoles = roles.count ? calloc(roles.count, sizeof(char *)) : NULL;
        const char **cContents = contents.count ? calloc(contents.count, sizeof(char *)) : NULL;
        for (NSUInteger i = 0; i < roles.count; i++) {
            cRoles[i] = roles[i].UTF8String;
            cContents[i] = contents[i].UTF8String;
        }
        BRPartialBox *box = [BRPartialBox new];
        box.partial = partial;
        err[0] = 0;
        char *out = br_engine_chat(self.engine, system.UTF8String ?: "", cRoles, cContents, (int)roles.count,
                                    user.UTF8String ?: "", 160, BRPartialThunk, (__bridge void *)box, err, sizeof(err));
        free(cRoles);
        free(cContents);
        NSString *text = out ? [NSString stringWithUTF8String:out] : nil;
        free(out);
        NSString *msg = err[0] ? [NSString stringWithUTF8String:err] : @"Modelul nu a răspuns.";
        dispatch_async(dispatch_get_main_queue(), ^{
            if (text.length) {
                if (done) done(text, nil);
            } else if (done) {
                done(nil, BRErr(msg));
            }
        });
    });
}
@end
