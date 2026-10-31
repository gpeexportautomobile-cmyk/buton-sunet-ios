#import <Foundation/Foundation.h>

@interface BRLlama : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) BOOL downloaded;
@property (nonatomic, readonly) BOOL downloading;
@property (nonatomic, readonly) float progress;
@property (nonatomic, readonly) unsigned long long fileBytes;
- (NSString *)statusText;
- (void)downloadWithProgress:(void (^)(float progress))progress completion:(void (^)(NSError *error))completion;
- (void)cancelDownload;
- (void)deleteModel;
- (void)replySystem:(NSString *)system
            history:(NSArray<NSDictionary *> *)history
               user:(NSString *)user
          onPartial:(void (^)(NSString *text))partial
               done:(void (^)(NSString *text, NSError *error))done;
@end
