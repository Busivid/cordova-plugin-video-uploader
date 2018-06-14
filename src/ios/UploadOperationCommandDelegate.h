#import <Cordova/CDVCommandDelegateImpl.h>
#import <Cordova/CDV.h>

@interface UploadOperationCommandDelegate:NSObject<CDVCommandDelegate>

@property (nonatomic, copy) void (^completionBlock)(NSString *errorMessage);

- (id) initWithCommandDelegateImpl:(CDVCommandDelegateImpl *) commandDelegateImpl progressId:(NSString *) pId offset:(NSNumber *) offset totalBytes:(NSNumber *) totalBytes;

@end
