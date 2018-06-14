//
//  VideoUploader.m
//
//  Created by Cory Thompson on 2017-06-16
//

#import <Cordova/CDV.h>
#import "UploadOperation.h"
#import "TranscodeOperation.h"
#import "VideoUploader.h"

@implementation VideoUploader {
	UIBackgroundTaskIdentifier _backgroundTaskId;
	NSString *_latestCallbackId;
	NSObject *_transcodeCallbackLock;
	NSOperationQueue *_transcodeQueue;
	NSOperationQueue *_uploadQueue;
}

@synthesize completedUploads;

- (void) abort:(CDVInvokedUrlCommand *) cmd {
	[_transcodeQueue cancelAllOperations];
	[_uploadQueue cancelAllOperations];
	[self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK] callbackId:_latestCallbackId];
}

- (void) applicationDidEnterBackground:(UIApplication *) application {
	NSLog(@"[VideoUploader]: applicationDidEnterBackground called");

	// if stuff in queues, request a background task.
	if ([_transcodeQueue operationCount] > 0 || [_uploadQueue operationCount] > 0) {
		_backgroundTaskId = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
			NSString *errorMessage = @"Application was running too long in the background and iOS cancelled uploading. Please try again.";
			[self handleFatalError:errorMessage withCallbackId:_latestCallbackId];
			[self removeBackgroundTask];
		}];
	}
}

- (void) applicationWillEnterForeground:(UIApplication *) application {
	NSLog(@"[VideoUploader]: applicationWillEnterForeground called");

	[self removeBackgroundTask];
}

- (void) cleanUp:(CDVInvokedUrlCommand *) cmd {
	NSLog(@"[VideoUploader]: cleanUp called");

	[self.commandDelegate runInBackground:^{
		NSFileManager *fileMgr = [NSFileManager defaultManager];

		// delete compressed files from cache directory.
		NSString *cacheDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
		NSString *videoDir = [cacheDir stringByAppendingPathComponent:@"mp4"];
		NSArray *fileArray = [fileMgr contentsOfDirectoryAtPath:videoDir error:nil];
		for (NSString *filename in fileArray)  {
			if ([filename hasSuffix:@"_compressed.mp4"])
				[fileMgr removeItemAtPath:[videoDir stringByAppendingPathComponent:filename] error:NULL];
		}

		// delete temp files from picker / capture interface.
		NSString *tempDir = [NSTemporaryDirectory()stringByStandardizingPath];
		NSArray *tempFilesArray = [fileMgr contentsOfDirectoryAtPath:tempDir error:nil];
		for (NSString *tempFile in tempFilesArray) {
			if ([tempFile hasPrefix:@"cdv_photo"] || [tempFile hasSuffix:@".MOV"] || [tempFile hasPrefix:@"capture"])
				[fileMgr removeItemAtPath:[tempDir stringByAppendingPathComponent:tempFile] error:NULL];
		}

		[self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK] callbackId:cmd.callbackId];
	}];
}

- (void) compressAndUpload:(CDVInvokedUrlCommand *) cmd {
	NSLog(@"[VideoUploader]: compressAndUpload called");

	completedUploads = [[NSMutableArray alloc] init];
	_latestCallbackId = cmd.callbackId;

	[self.commandDelegate runInBackground:^{
		NSArray *fileOptions = [cmd.arguments objectAtIndex:0];
		for(NSDictionary *options in fileOptions) {
			NSString *progressId = options[@"progressId"];

			// Find a temporary path for transcoding.
			NSString *transcodingDstFilePath = [self getTempTranscodingFile:progressId];
			if (transcodingDstFilePath == nil) {
				[self handleFatalError:@"Unable to create output folder for compression." withCallbackId:_latestCallbackId];
				return;
			}

			// Get all required parameters from options.
			NSURL *transcodingDst = [NSURL fileURLWithPath:transcodingDstFilePath];
			NSURL *transcodingSrc = [NSURL URLWithString:options[@"filePath"]];

			NSURL *uploadCompleteUrl = [NSURL URLWithString:options[@"callbackUrl"]];
			NSString *uploadCompleteUrlAuthorization = options[@"callbackUrlAuthorization"];
			NSMutableDictionary *uploadCompleteUrlFields = [[NSMutableDictionary alloc] init];
			if (options[@"callbackUrlFields"] != nil) {
				NSDictionary *callbackUrlFields = options[@"callbackUrlFields"];
				[uploadCompleteUrlFields addEntriesFromDictionary:callbackUrlFields];
			}

			NSString *uploadCompleteUrlMethod = options[@"callbackUrlMethod"] == nil
				? @"GET"
				: options[@"callbackUrlMethod"];

			NSURL *uploadUrl = [NSURL URLWithString:options[@"uploadUrl"]];

			// Initialise UploadOperation which is added to _uploadQueue on completetionBlock of transcoding operation
			UploadOperation *uploadOperation = [[UploadOperation alloc] initWithOptions:options commandDelegate:self.commandDelegate cordovaCallbackId:_latestCallbackId];
			[uploadOperation setTarget:uploadUrl];
			[uploadOperation setUploadCompleteUrl:uploadCompleteUrl];
			[uploadOperation setUploadCompleteUrlAuthorization:uploadCompleteUrlAuthorization];
			[uploadOperation setUploadCompleteUrlMethod:uploadCompleteUrlMethod];

			[uploadOperation addUploadCompleteUrlFields:uploadCompleteUrlFields];

			__weak UploadOperation *weakUpload = uploadOperation;
			[weakUpload setCompletionBlock:^{
				if (weakUpload.errorMessage != nil) {
					[self handleFatalError:weakUpload.errorMessage withCallbackId:_latestCallbackId];
					return;
				}

				if (weakUpload.isCancelled)
					return;

				[completedUploads addObject:progressId];

				// Notify cordova a single upload is complete
				[self reportProgress:_latestCallbackId progress:[NSNumber numberWithInt:100] progressId:progressId type:@"PROGRESS_UPLOADED"];

				if ([_transcodeQueue operationCount] == 0 && [_uploadQueue operationCount] == 0) {
					NSLog(@"[Done]");

					// Notify cordova all operations are complete
					[self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK] callbackId:_latestCallbackId];
					[self removeBackgroundTask];
				}
			}];

			// Initialise TranscodeOperation which is added immediately to queue.
			TranscodeOperation *transcodeOperation = [[TranscodeOperation alloc] initWithFilePath:transcodingSrc dst:transcodingDst options:options commandDelegate:self.commandDelegate cordovaCallbackId:_latestCallbackId];

			__weak TranscodeOperation *weakTranscodeOperation = transcodeOperation;
			[transcodeOperation setCompletionBlock:^{
				// Mutex lock to fix race conditions.
				// If two task have already been transcoded, therefore return instantly, the UploadOperations can be added out of order and looks confusing on the UI.
				@synchronized (_transcodeCallbackLock) {
					if (weakTranscodeOperation.isCancelled)
						return;

					if (weakTranscodeOperation.errorMessage != nil) {
						// Notify cordova a single transcode errored.
						[self reportProgress:_latestCallbackId progress:[NSNumber numberWithInt:100] progressId:progressId type:@"PROGRESS_TRANSCODING_ERROR"];

						// Transcoded failed, use original file in upload
						[uploadOperation setSource:transcodingSrc];
					} else {
						// Notify cordova a single transcode is complete
						[self reportProgress:_latestCallbackId progress:[NSNumber numberWithInt:100] progressId:progressId type:@"PROGRESS_TRANSCODED"];

						NSFileManager *fileMgr = [NSFileManager defaultManager];
						unsigned long long transcodingDstFileSize = [[fileMgr attributesOfItemAtPath:transcodingDst.path error:nil] fileSize];
						unsigned long long transcodingSrcFileSize = [[fileMgr attributesOfItemAtPath:transcodingSrc.path error:nil] fileSize];

						// Upload the smaller file size
						NSURL *fileToUpload = transcodingSrcFileSize >= transcodingDstFileSize
							? transcodingDst
							: transcodingSrc;

						// Use transcoded file in upload
						[uploadOperation setSource:fileToUpload];
					}

					// Add uploading to queue
					[_uploadQueue addOperation:uploadOperation];
				}
			}];

			[_transcodeQueue addOperation:transcodeOperation];
		}
	}];
}

- (NSString *) getTempTranscodingFile:(NSString *) progressId {
	// Ensure the cache directory exists.
	NSFileManager *fileMgr = [NSFileManager defaultManager];
	NSString *cacheDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
	NSString *videoDir = [cacheDir stringByAppendingPathComponent:@"mp4"];

	if ([fileMgr createDirectoryAtPath:videoDir withIntermediateDirectories:YES attributes:nil error: NULL] == NO)
		return nil;

	// Get a unique compressed file name.
	NSString *videoOutput = [videoDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", [NSString stringWithFormat:@"%@_compressed", progressId], @"mp4"]];
	return videoOutput;
}

- (void) handleFatalError:(NSString *) message withCallbackId:(NSString *) callbackId {
	NSLog(@"[VideoUploader]: handleFatalError called");

	NSMutableDictionary *results = [NSMutableDictionary dictionaryWithCapacity:2];
	[results setObject:message forKey:@"message"];
	[results setObject:completedUploads forKey:@"completedUploads"];

	[_transcodeQueue cancelAllOperations];
	[_uploadQueue cancelAllOperations];
	if ([[UIApplication sharedApplication] applicationState] == UIApplicationStateBackground) {

		// If we are in the background, display the error message as a local push notification
		UILocalNotification *notification = [[UILocalNotification alloc]init];
		notification.alertAction = nil;
		notification.alertBody = message;
		notification.fireDate = [NSDate dateWithTimeIntervalSinceNow:5];
		notification.repeatInterval = 0;
		notification.soundName = UILocalNotificationDefaultSoundName;

		[[UIApplication sharedApplication]scheduleLocalNotification:notification];
	}

	[self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:results] callbackId:callbackId];
}

- (void) pluginInitialize {
	NSLog(@"[VideoUploader]: pluginInitalize called");

	_backgroundTaskId = UIBackgroundTaskInvalid;

	_transcodeQueue = [[NSOperationQueue alloc] init];
	_transcodeQueue.maxConcurrentOperationCount = 1;

	_uploadQueue = [[NSOperationQueue alloc] init];
	_uploadQueue.maxConcurrentOperationCount = 1;
}

- (void) removeBackgroundTask {
	NSLog(@"[VideoUploader]: removeBackgroundTask called");

	if (_backgroundTaskId != UIBackgroundTaskInvalid) {
		[[UIApplication sharedApplication] endBackgroundTask:_backgroundTaskId];
		_backgroundTaskId = UIBackgroundTaskInvalid;
	}
}

- (void) reportProgress:(NSString *) callbackId progress:(NSNumber *) progress progressId:(NSString *) progressId type:(NSString *) type {
	NSMutableDictionary *dictionary = [[NSMutableDictionary alloc] init];
	[dictionary setValue: progress forKey: @"progress"];
	[dictionary setValue: progressId forKey: @"progressId"];
	[dictionary setValue: type forKey: @"type"];
	CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary: dictionary];
	[result setKeepCallbackAsBool:YES];
	[self.commandDelegate sendPluginResult:result callbackId:callbackId];
}

@end
