#import <Cordova/CDV.h>
#import "CDVFile.h"
#import "CDVFileTransfer.h"
#import "BVTranscodeOperation.h"

@interface BVUploadOperation : NSOperation

@property (readonly) NSString *errorMessage;
@property (copy) NSURL *source;
@property (copy) NSURL *target;
@property (copy) NSURL *uploadCompleteUrl;
@property (copy) NSString *uploadCompleteUrlAuthorization;
@property (copy) NSString *uploadCompleteUrlMethod;

- (void) addUploadCompleteUrlFields:(NSDictionary *) dict;
- (void) cancel;
- (id) initWithOptions:(NSDictionary *) opts commandDelegate:(id <CDVCommandDelegate>) cmdDelegate cordovaCallbackId:(NSString *) callbackId;
- (void) main;
@end
