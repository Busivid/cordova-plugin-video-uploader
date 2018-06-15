#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import "BVTranscodeOperation.h"

@implementation BVTranscodeOperation {
	id <CDVCommandDelegate> __weak _commandDelegate;
	NSString *_cordovaCallbackId;
	NSURL *_dstPath;
	AVAssetExportSession *exportSession;
	NSURL *_srcPath;
	NSNumber *_videoDuration;
}

@synthesize errorMessage;
@synthesize progressId;

- (void) cancel {
	[super cancel];
	if (exportSession != nil) {
		[exportSession cancelExport];
	}
}

- (id) initWithFilePath:(NSURL *) src dst:(NSURL *) dst options:(NSDictionary *) options commandDelegate:(id <CDVCommandDelegate>) delegate cordovaCallbackId:(NSString *) callbackId
{
	if (![super init])
		return nil;

	NSLog(@"Transcode options %@", options);
	_commandDelegate = delegate;
	_cordovaCallbackId = callbackId;
	_dstPath = dst;
	progressId = options[@"progressId"];
	_srcPath = src;
	_videoDuration = options[@"maxSeconds"];

	return self;
}

- (void) main {
	NSLog(@"[BVTranscodeOperation]: inputFilePath: %@", _srcPath);
	NSLog(@"[BVTranscodeOperation]: outputPath: %@", _dstPath);

	if (self.isCancelled)
		return;

	if ([[NSFileManager defaultManager] fileExistsAtPath:_dstPath.path])
		return;

	AVURLAsset *avAsset = [AVURLAsset URLAssetWithURL:_srcPath options:nil];

	exportSession = [[AVAssetExportSession alloc]initWithAsset:avAsset presetName: AVAssetExportPreset1280x720];
	exportSession.outputURL = _dstPath;
	exportSession.outputFileType = AVFileTypeQuickTimeMovie;
	exportSession.shouldOptimizeForNetworkUse = YES;

	int32_t preferredTimeScale = 600;
	CMTime startTime = CMTimeMakeWithSeconds(0, preferredTimeScale);
	CMTime stopTime = CMTimeMakeWithSeconds([_videoDuration floatValue], preferredTimeScale);
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
		if (self.isCancelled)
			return;

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

	// We need to ensure a status progress of 100 was sent at some point.
	if ([exportSession status] == AVAssetExportSessionStatusCompleted) {
		[self reportProgress:[NSNumber numberWithInt:100]];
	}

	if ([exportSession status] != AVAssetExportSessionStatusCompleted)
		[[NSFileManager defaultManager] removeItemAtPath:_dstPath.path error:nil];

	switch ([exportSession status]) {
		case AVAssetExportSessionStatusCompleted:
			NSLog(@"[BVTranscodeOperation]: Export Complete %ld %@", (long)exportSession.status, exportSession.error);
			break;

		case AVAssetExportSessionStatusFailed:
			NSLog(@"[BVTranscodeOperation]: Export failed: %@", [[exportSession error] localizedDescription]);
			errorMessage = [[exportSession error] localizedDescription];
			 break;

		case AVAssetExportSessionStatusCancelled:
			NSLog(@"[BVTranscodeOperation]: Export canceled");
			break;

		default:
			NSLog(@"[BVTranscodeOperation]: Export default in switch");
			break;
	}
}

// Forwards progress up to Javascript.
- (void) reportProgress:(NSNumber *) progress {
	NSLog(@"%@", [NSString stringWithFormat:@"AVAssetExport running progress=%3.2f%%", [progress doubleValue]]);

	if (_commandDelegate != nil && _cordovaCallbackId != nil) {
		NSMutableDictionary *dictionary = [[NSMutableDictionary alloc] init];
		[dictionary setValue: progress forKey: @"progress"];
		[dictionary setValue: progressId forKey: @"progressId"];
		[dictionary setValue: @"PROGRESS_TRANSCODING" forKey: @"type"];

		CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary: dictionary];

		[result setKeepCallbackAsBool:YES];
		[_commandDelegate sendPluginResult:result callbackId:_cordovaCallbackId];
	}
}

@end
