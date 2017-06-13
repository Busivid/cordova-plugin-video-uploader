#import "TranscodeOperation.h"
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@implementation TranscodeOperation

@synthesize callbackId;
@synthesize commandDelegate;
@synthesize dstPath;
@synthesize errorMessage;
@synthesize maxSeconds;
@synthesize srcPath;
@synthesize progressId;
@synthesize exportSession;

- (id)initWithSrc:(NSURL *)src dst:(NSURL*)dst maxSeconds:(Float64)seconds progressId:(NSString*)pId
{
    if (![super init]) return nil;
    [self setDstPath:dst];
    [self setMaxSeconds:seconds];
    [self setSrcPath:src];
    [self setProgressId:pId];
    return self;
}

- (void)reportProgress:(NSNumber*)progress {
    NSLog(@"%@", [NSString stringWithFormat:@"AVAssetExport running progress=%3.2f%%", [progress doubleValue]]);

    if (self.commandDelegate != NULL && self.callbackId != NULL) {
    	NSMutableDictionary *dictionary = [[NSMutableDictionary alloc] init];
    	[dictionary setValue: progress forKey: @"progress"];
        [dictionary setValue: progressId forKey: @"progressId"];
        [dictionary setValue: @"TRANSCODING" forKey: @"type"];

    	CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary: dictionary];

    	[result setKeepCallbackAsBool:YES];
    	[self.commandDelegate sendPluginResult:result callbackId:callbackId];
    }

}

- (void)cancel {
    [super cancel];
    if (exportSession != nil) {
        [exportSession cancelExport];
    }
}

- (void)main {
    NSLog(@"[TranscodeOperation]: inputFilePath: %@", srcPath);
    NSLog(@"[TranscodeOperation]: outputPath: %@", dstPath);

    if (self.isCancelled) {
        return;
    }

    AVURLAsset *avAsset = [AVURLAsset URLAssetWithURL:srcPath options:nil];

    exportSession = [[AVAssetExportSession alloc]initWithAsset:avAsset presetName: AVAssetExportPreset1280x720];
    exportSession.outputURL = dstPath;
    exportSession.outputFileType = AVFileTypeQuickTimeMovie;
    exportSession.shouldOptimizeForNetworkUse = YES;

    int32_t preferredTimeScale = 600;
    CMTime startTime = CMTimeMakeWithSeconds(0, preferredTimeScale);
    CMTime stopTime = CMTimeMakeWithSeconds(maxSeconds, preferredTimeScale);
    CMTimeRange exportTimeRange = CMTimeRangeFromTimeToTime(startTime, stopTime);
    exportSession.timeRange = exportTimeRange;

    // Set up a semaphore for the completion handler and progress timer
    dispatch_semaphore_t sessionWaitSemaphore = dispatch_semaphore_create(0);

    void (^completionHandler)(void) = ^(void)
    {
        dispatch_semaphore_signal(sessionWaitSemaphore);
    };

    // GPU operations AND a new thread cannot be produced while in the background mode.
    // Wait until we are in the foreground before spawning a new render process.
    while ([[UIApplication sharedApplication] applicationState] == UIApplicationStateBackground) {
        if (self.isCancelled) {
            return;
        }
        [NSThread sleepForTimeInterval:0.1];
    }
    [exportSession exportAsynchronouslyWithCompletionHandler:completionHandler];

    do {
        double progress = [exportSession progress] * 100;
        [self reportProgress:[NSNumber numberWithDouble:progress]];

        // Wait 1 second or until the the semaphore is called from completionHandler above.
        double delayInSeconds = 1;
        dispatch_time_t dispatchTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
        dispatch_semaphore_wait(sessionWaitSemaphore, dispatchTime);
    } while( [exportSession status] < AVAssetExportSessionStatusCompleted );

    // We need to ensure a status progress of 100 was sent at 	some point.
    if ([exportSession status] == AVAssetExportSessionStatusCompleted) {
        if (self.commandDelegate != NULL && self.callbackId != NULL) {
            [self reportProgress:[NSNumber numberWithInt:100]];
        }
    }

    switch ([exportSession status]) {
        case AVAssetExportSessionStatusCompleted:
            NSLog(@"[TranscodeOperation]: Export Complete %ld %@", (long)exportSession.status, exportSession.error);
            break;
        case AVAssetExportSessionStatusFailed:
            NSLog(@"[TranscodeOperation]: Export failed: %@", [[exportSession error] localizedDescription]);
            errorMessage = [[exportSession error] localizedDescription];
             break;
        case AVAssetExportSessionStatusCancelled:
            NSLog(@"[TranscodeOperation]: Export canceled");
            break;
        default:
            NSLog(@"[TranscodeOperation]: Export default in switch");
            break;
    }
}

@end
