#import <Cordova/CDV.h>
#import "CDVFile.h"
#import "CDVFileTransfer.h"
#import "TranscodeOperation.h"

@interface UploadOperation : NSOperation {
	id <CDVCommandDelegate> __weak commandDelegate;
	NSString *cordovaCallbackId;
	CDVFileTransfer *fileTransfer;
	NSDictionary *options;
	NSURL *source;
	NSURL *target;
}

@property (retain) NSString *errorMessage;
@property (retain) NSURL *source;
@property (retain) NSURL *target;
@property (copy) NSURL *uploadCompleteUrl;
@property (copy) NSString *uploadCompleteUrlAuthorization;
@property (copy) NSString *uploadCompleteUrlMethod;

- (void) addUploadCompleteUrlFields:(NSDictionary *) dict;
- (void) cancel;
- (id) initWithOptions:(NSDictionary *) opts commandDelegate:(id <CDVCommandDelegate>) cmdDelegate cordovaCallbackId:(NSString*) callbackId;
- (void) main;
@end
