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

@property (nonatomic, weak) id <CDVCommandDelegate> commandDelegate;
@property(retain) NSString *errorMessage;
@property (copy) NSURL* uploadCompleteUrl;

- (void)cancel;
- (id)initWithSource:(NSURL*)source target:(NSURL*)target options:(NSDictionary *)opts commandDelegate:(id <CDVCommandDelegate>)cmdDelegate cordovaCallbackId:(NSString*)callbackId;
- (void)main;
@end
