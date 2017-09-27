#import <Cordova/CDVCommandDelegateImpl.h>
#import <Cordova/CDV.h>

@interface UploadOperationCommandDelegate:NSObject<CDVCommandDelegate> {
	CDVCommandDelegateImpl* commandDelegate;
	NSNumber* lastReportedProgress;
	NSNumber* offset;
	NSString* progressId;
	NSNumber* totalBytes;
}
@property (nonatomic, copy) void (^completionBlock)(NSString* errorMessage);

- (id) initWithCommandDelegateImpl:(CDVCommandDelegateImpl*) commandDelegateImpl progressId:(NSString*) pId offset:(NSNumber*) offset totalBytes:(NSNumber*) totalBytes;
@end
