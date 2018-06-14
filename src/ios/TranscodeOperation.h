#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import <Cordova/CDV.h>

@interface TranscodeOperation : NSOperation

@property (nonatomic, weak) id <CDVCommandDelegate> commandDelegate;
@property (retain) NSString *errorMessage;

- (void) cancel;
- (id) initWithFilePath:(NSURL*) src dst:(NSURL*)dst options:(NSDictionary *) options commandDelegate:(id <CDVCommandDelegate>) cmdDelegate cordovaCallbackId:(NSString*) callbackId;
- (void) main;

@end
