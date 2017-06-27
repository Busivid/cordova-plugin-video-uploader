//
//  VideoUploader.m
//
//  Created by Cory Thompson on 2017-06-16
//

#import <Cordova/CDV.h>
#import "VideoUploader.h"
#import "UploadOperation.h"
#import "TranscodeOperation.h"

@implementation VideoUploader

@synthesize backgroundTaskID;
@synthesize command;
@synthesize completedTransfers;
@synthesize transcodingQueue;
@synthesize uploadQueue;

/*
 * Functions available via Cordova
 */
- (void) cleanUp:(CDVInvokedUrlCommand*)cmd {
    NSLog(@"[VideoUploader]: cleanUp called");

    [self.commandDelegate runInBackground:^{
        NSFileManager *fileMgr = [NSFileManager defaultManager];

        // delete compressed files from cache directory.
        NSString *cacheDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
        NSString *videoDir = [cacheDir stringByAppendingPathComponent:@"mp4"];
        NSArray *fileArray = [fileMgr contentsOfDirectoryAtPath:videoDir error:nil];
        for (NSString *filename in fileArray)  {
            if ([filename hasSuffix:@"_compressed.mp4"]) {
                [fileMgr removeItemAtPath:[videoDir stringByAppendingPathComponent:filename] error:NULL];
            }
        }

        // delete temp files from picker / capture interface.
        NSString *tempDir = [NSTemporaryDirectory()stringByStandardizingPath];
        NSArray *tempFilesArray = [fileMgr contentsOfDirectoryAtPath:tempDir error:nil];
        for (NSString *tempFile in tempFilesArray) {
            if ([tempFile hasPrefix:@"cdv_photo"] || [tempFile hasSuffix:@".MOV"]) {
                [fileMgr removeItemAtPath:[tempDir stringByAppendingPathComponent:tempFile] error:NULL];
            }
        }

        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK] callbackId:cmd.callbackId];
    }];
}

- (void) compressAndUpload:(CDVInvokedUrlCommand*)cmd {
    NSLog(@"[VideoUploader]: compressAndUpload called");

    completedTransfers = [[NSMutableArray alloc] init];

    [self.commandDelegate runInBackground:^{
        self.command = cmd;
        NSArray *fileOptions = [command.arguments objectAtIndex:0];

        for(NSDictionary *file in fileOptions) {
            NSString *callbackUrl = file[@"callbackUrl"];
            NSString *fileName = file[@"fileName"];
            NSString *filePathString = [file[@"filePath"] stringByReplacingOccurrencesOfString:@"file://"
                                                                        withString:@""];
            NSNumber *maxSeconds = file[@"maxSeconds"];
            NSDictionary *params = file[@"params"];
            NSString *progressId = file[@"progressId"];
            NSNumber *timeout = file[@"timeout"];
            NSString *uploadUrl = file[@"uploadUrl"];
            
            NSNumber *fileLengthLimit = file[@"fileLengthLimit"];
            if (fileLengthLimit == nil) {
                //default the value to no limit
                fileLengthLimit = [NSNumber numberWithInt:0];
            }

            NSURL *filePath = [[NSURL alloc] initFileURLWithPath:filePathString];

            UploadParameters *uploadParams = [[UploadParameters alloc] init];
            uploadParams.callbackUrl = callbackUrl;
            uploadParams.chunkMode = true;
            uploadParams.fileKey = @"file";
            uploadParams.fileName = fileName;
            // uploadParams.filePath = filePath;
            uploadParams.mimeType = @"video/mpeg";
            uploadParams.params = params;
            uploadParams.progressId = progressId;
            uploadParams.timeout = timeout;
            uploadParams.uploadUrl = uploadUrl;

            TranscodeOperation *transcodeOperation = [self getTranscodeOperationWithSrc:filePath maxSeconds:[maxSeconds floatValue] fileLengthLimit:fileLengthLimit progressId:progressId uploadParams:uploadParams];
            if (transcodeOperation == nil) {
                // If nil, an error has occured and event has already been raised
                // just stop adding stuff to queue.
                return;
            }

            [transcodingQueue addOperation:transcodeOperation];
        }
    }];
}

- (void) abort:(CDVInvokedUrlCommand*)cmd {
    [transcodingQueue cancelAllOperations];
    [uploadQueue cancelAllOperations];
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK] callbackId:cmd.callbackId];
}

/*
 * Helper functions
 */

- (NSString *)getUUID
{
    CFUUIDRef newUniqueId = CFUUIDCreate(kCFAllocatorDefault);
    NSString * uuidString = (__bridge_transfer NSString*)CFUUIDCreateString(kCFAllocatorDefault, newUniqueId);
    CFRelease(newUniqueId);

    return uuidString;
}

- (void) handleFatalError:(NSString*)message {
    NSLog(@"[VideoUploader]: handleFatalError called");

    NSMutableDictionary *results = [NSMutableDictionary dictionaryWithCapacity:2];
    [results setObject:message forKey:@"message"];
    [results setObject:completedTransfers forKey:@"completedTransfers"];

    [transcodingQueue cancelAllOperations];
    [uploadQueue cancelAllOperations];
    if ([[UIApplication sharedApplication] applicationState] == UIApplicationStateBackground) {

    	// If we are in the background, display the error message as a local push notification
        UILocalNotification *notification = [[UILocalNotification alloc]init];
    	notification.alertAction = nil;
    	notification.soundName = UILocalNotificationDefaultSoundName;
    	notification.alertBody = message;
    	notification.soundName = UILocalNotificationDefaultSoundName;
    	notification.fireDate = [NSDate dateWithTimeIntervalSinceNow:5];
    	notification.repeatInterval = 0;

    	[[UIApplication sharedApplication]scheduleLocalNotification:notification];
    }

    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:results] callbackId:command.callbackId];
}

- (TranscodeOperation*) getTranscodeOperationWithSrc:(NSURL*)src maxSeconds:(Float64)maxSeconds fileLengthLimit:(NSNumber*)fileLengthLimit progressId:(NSString*)progressId uploadParams:(UploadParameters*)uploadParams {
    NSLog(@"[VideoUploader]: getTranscodeOperationWithSrc called");

    // Ensure the cache directory exists.
    NSFileManager *fileMgr = [NSFileManager defaultManager];
    NSString *cacheDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString *videoDir = [cacheDir stringByAppendingPathComponent:@"mp4"];
    if ([fileMgr createDirectoryAtPath:videoDir withIntermediateDirectories:YES attributes:nil error: NULL] == NO){
        [self handleFatalError:@"Unable to create output folder for compression."];
        return nil;
    }

    // Get a unique compressed file name.
    NSString *videoOutput = [videoDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", [NSString stringWithFormat:@"%@_compressed", [self getUUID]], @"mp4"]];
    NSURL *dst = [NSURL fileURLWithPath:videoOutput];

    //Initialise transcodeOperation.
    TranscodeOperation *transcodeOperation = [[TranscodeOperation alloc] initWithSrc:src dst:dst maxSeconds:maxSeconds fileLengthLimit:fileLengthLimit progressId:progressId];
    __weak TranscodeOperation *weakTranscode = transcodeOperation;
    [transcodeOperation setCompletionBlock:^{
        if (weakTranscode.errorMessage != nil) {
            [self handleFatalError:weakTranscode.errorMessage];
            return;
        }

        if (weakTranscode.isCancelled) {
            return;
        }

        // queue upload
        uploadParams.filePath = dst.path;
        UploadOperation *uploadOperation = [self getUploadOperationWithSrc:uploadParams];
        [uploadQueue addOperation:uploadOperation];
    }];

    [transcodeOperation setCommandDelegate:self.commandDelegate];
    [transcodeOperation setCallbackId: command.callbackId];

    return transcodeOperation;
}

- (UploadOperation*)getUploadOperationWithSrc:(UploadParameters*)uploadParams {
    NSLog(@"[VideoUploader]: getUploadOperationWithSrc called");

    UploadOperation *uploadOperation = [[UploadOperation alloc] init];
    [uploadOperation setCommandDelegate:self.commandDelegate];
    [uploadOperation setCallbackId: command.callbackId];
    [uploadOperation setParameters:uploadParams];

    __weak UploadOperation *weakUpload = uploadOperation;
    [uploadOperation setCompletionBlock:^{
        if (weakUpload.errorMessage != nil) {
            [self handleFatalError:weakUpload.errorMessage];
            return;
        }

        if (weakUpload.isCancelled){
            return;
        }

        [completedTransfers addObject:weakUpload.parameters.progressId];

        // Notify cordova a single upload is complete.
        NSMutableDictionary *dictionary = [[NSMutableDictionary alloc] init];
        [dictionary setValue: [NSNumber numberWithInt:100] forKey: @"progress"];
        [dictionary setValue: weakUpload.parameters.progressId forKey: @"progressId"];
        [dictionary setValue: @"UPLOADCOMPLETE" forKey: @"type"];
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary: dictionary];
        [result setKeepCallbackAsBool:YES];
        [self.commandDelegate sendPluginResult:result callbackId:self.command.callbackId];

        if ([transcodingQueue operationCount] == 0 && [uploadQueue operationCount] == 0) {
            NSLog(@"[Done]");
            // Notify cordova ALL uploads / transcodes are complete.
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK] callbackId:self.command.callbackId];

            [self removeBackgroundTask];
        }
    }];

    return uploadOperation;
}

- (void) removeBackgroundTask {
    NSLog(@"[VideoUploader]: removeBackgroundTask called");

    if (backgroundTaskID != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:backgroundTaskID];
        backgroundTaskID = UIBackgroundTaskInvalid;
    }
}

/*
 * Events
 */

- (void) pluginInitialize {
    NSLog(@"[VideoUploader]: pluginInitalize called");

    backgroundTaskID = UIBackgroundTaskInvalid;

    transcodingQueue = [[NSOperationQueue alloc] init];
    transcodingQueue.maxConcurrentOperationCount = 1;

    uploadQueue = [[NSOperationQueue alloc] init];
    uploadQueue.maxConcurrentOperationCount = 1;
}

- (void)applicationWillEnterForeground:(UIApplication*)application {
    NSLog(@"[VideoUploader]: applicationWillEnterForeground called");

    [self removeBackgroundTask];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    NSLog(@"[VideoUploader]: applicationDidEnterBackground called");

    // if stuff in queues, request a background task.
    if ([transcodingQueue operationCount] > 0 || [uploadQueue operationCount] > 0) {
    	backgroundTaskID = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
            NSString* errorMessage = @"Application was running too long in the background and iOS cancelled uploading. Please try again.";
            [self handleFatalError:errorMessage];
            [self removeBackgroundTask];

    	}];
    }
}
@end
