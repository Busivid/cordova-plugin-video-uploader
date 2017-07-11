#import <Cordova/CDVCommandDelegateImpl.h>
#import <Cordova/CDV.h>

@interface UploadOperationCommandDelegate:NSObject<CDVCommandDelegate> {
    CDVCommandDelegateImpl* commandDelegate;
    NSNumber* lastReportedProgress;
    NSString* progressId;
}
@property (nonatomic, copy) void (^completionBlock)(NSString* errorMessage);

- (id)initWithCommandDelegateImpl:(CDVCommandDelegateImpl*)commandDelegateImpl withProgressId:(NSString*)pId;
@end
