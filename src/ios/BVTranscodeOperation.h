#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import <Cordova/CDV.h>

@interface BVTranscodeOperation : NSOperation

@property (readonly) NSString *errorMessage;

- (void) cancel;
- (id) initWithFilePath:(NSURL*) src dst:(NSURL*)dst options:(NSDictionary *) options commandDelegate:(id <CDVCommandDelegate>) cmdDelegate cordovaCallbackId:(NSString*) callbackId;
- (void) main;

@end
