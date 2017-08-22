#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import <Cordova/CDV.h>

@interface TranscodeOperation : NSOperation {
    id <CDVCommandDelegate> __weak commandDelegate;
    NSString *cordovaCallbackId;
    NSURL *dstPath;
    AVAssetExportSession *exportSession;
    NSString *progressId;
    NSURL *srcPath;
    NSNumber *videoDuration;
    NSNumber *width;

    //NSNumber *fps;
    //NSNumber *height;
    //NSNumber *videoBitrate;
}

@property (nonatomic, weak) id <CDVCommandDelegate> commandDelegate;
@property(retain) NSString *errorMessage;

- (void)cancel;
- (id)initWithFilePath:(NSURL*)src dst:(NSURL*)dst options:(NSDictionary *)options commandDelegate:(id <CDVCommandDelegate>)cmdDelegate cordovaCallbackId:(NSString*)callbackId;
- (void)main;

@end
