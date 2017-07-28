//
//  VideoUploader.m
//
//  Created by Cory Thompson on 2017-06-16
//

#import <Cordova/CDV.h>
#import "UploadOperation.h"
#import "TranscodeOperation.h"
#import "VideoUploader.h"

@implementation VideoUploader
@synthesize completedTransfers;

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
            if ([tempFile hasPrefix:@"cdv_photo"] || [tempFile hasSuffix:@".MOV"] || [tempFile hasPrefix:@"capture"]) {
                [fileMgr removeItemAtPath:[tempDir stringByAppendingPathComponent:tempFile] error:NULL];
            }
        }
        
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK] callbackId:cmd.callbackId];
    }];
}

- (void)compressAndUpload:(CDVInvokedUrlCommand*)cmd {
    NSLog(@"[VideoUploader]: compressAndUpload called");
    
    completedTransfers = [[NSMutableArray alloc] init];
    latestCallbackId = cmd.callbackId;
    
    [self.commandDelegate runInBackground:^{
        NSArray *fileOptions = [cmd.arguments objectAtIndex:0];
        for(NSDictionary *options in fileOptions) {
            NSString *progressId = options[@"progressId"];
            
            // Find a temporary path for transcoding.
            NSString *transcodingDstFilePath = [self getTempTranscodingFile:progressId];
            if (transcodingDstFilePath == nil) {
                [self handleFatalError:@"Unable to create output folder for compression." withCallbackId:latestCallbackId];
                return;
            }
            
            // Get all required parameters from options.
            NSURL *transcodingDst = [NSURL fileURLWithPath:transcodingDstFilePath];
            NSURL *transcodingSrc = [NSURL URLWithString:options[@"filePath"]];
            NSURL *uploadCompleteUrl = [NSURL URLWithString:options[@"callbackUrl"]];
            NSURL *uploadUrl = [NSURL URLWithString:options[@"uploadUrl"]];
            
            // Initialise UploadOperation which is added to UploadQueue on completetionBlock of transcoding operation
            UploadOperation *uploadOperation = [[UploadOperation alloc] initWithOptions:options commandDelegate:self.commandDelegate cordovaCallbackId:latestCallbackId];
            [uploadOperation setUploadCompleteUrl:uploadCompleteUrl];
            [uploadOperation setTarget:uploadUrl];
            
            __weak UploadOperation *weakUpload = uploadOperation;
            [weakUpload setCompletionBlock:^{
                if (weakUpload.errorMessage != nil) {
                    [self handleFatalError:weakUpload.errorMessage withCallbackId:latestCallbackId];
                    return;
                }
                
                if (weakUpload.isCancelled){
                    return;
                }
                
                [completedTransfers addObject:progressId];
                
                // Notify cordova a single upload is complete
                [self reportProgress:latestCallbackId progress:[NSNumber numberWithInt:100] progressId:progressId type:@"UPLOAD_COMPLETE"];
                
                if ([transcodingQueue operationCount] == 0 && [uploadQueue operationCount] == 0) {
                    NSLog(@"[Done]");
                    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK] callbackId:latestCallbackId];
                    [self removeBackgroundTask];
                }
            }];
            
            // Initialise TranscodeOperation which is added immediately to queue.
            TranscodeOperation *transcodeOperation = [[TranscodeOperation alloc] initWithFilePath:transcodingSrc dst:transcodingDst options:options commandDelegate:self.commandDelegate cordovaCallbackId:latestCallbackId];
            __weak TranscodeOperation* weakTranscodeOperation = transcodeOperation;
            [transcodeOperation setCompletionBlock:^{
                // Mutex lock to fix race conditions.
                // If two task have already been transcoded, therefore return instantly, the UploadOperations can be added out of order and looks confusing on the UI.
                @synchronized (transcodeCallbackLock) {
                    if (weakTranscodeOperation.isCancelled){
                        return;
                    }
                    
                    if (weakTranscodeOperation.errorMessage != nil) {
                        // Notify cordova a single transcode errored.
                        [self reportProgress:latestCallbackId progress:[NSNumber numberWithInt:100] progressId:progressId type:@"TRANSCODE_ERROR"];
                        
                        // Transcoded failed, use original file in upload
                        [uploadOperation setSource:transcodingSrc];
                    } else {
                        // Notify cordova a single transcode is complete
                        [self reportProgress:latestCallbackId progress:[NSNumber numberWithInt:100] progressId:progressId type:@"TRANSCODE_COMPLETE"];
                        
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
                    [uploadQueue addOperation:uploadOperation];
                }
            }];
            
            [transcodingQueue addOperation:transcodeOperation];
        }
    }];
}

- (void) abort:(CDVInvokedUrlCommand*)cmd {
    [transcodingQueue cancelAllOperations];
    [uploadQueue cancelAllOperations];
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK] callbackId:latestCallbackId];
}

/*
 * Helper functions
 */
- (void) handleFatalError:(NSString*)message withCallbackId:(NSString*)callbackId {
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
    
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:results] callbackId:callbackId];
}

- (NSString*)getTempTranscodingFile:(NSString*)progressId {
    // Ensure the cache directory exists.
    NSFileManager *fileMgr = [NSFileManager defaultManager];
    NSString *cacheDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString *videoDir = [cacheDir stringByAppendingPathComponent:@"mp4"];
    if ([fileMgr createDirectoryAtPath:videoDir withIntermediateDirectories:YES attributes:nil error: NULL] == NO){
        return nil;
    }
    // Get a unique compressed file name.
    NSString *videoOutput = [videoDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", [NSString stringWithFormat:@"%@_compressed", progressId], @"mp4"]];
    return videoOutput;
}

- (void)reportProgress:(NSString*)callbackId progress:(NSNumber*)progress progressId:(NSString*)progressId type:(NSString*)type {
    NSMutableDictionary *dictionary = [[NSMutableDictionary alloc] init];
    [dictionary setValue: progress forKey: @"progress"];
    [dictionary setValue: progressId forKey: @"progressId"];
    [dictionary setValue: type forKey: @"type"];
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary: dictionary];
    [result setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:result callbackId:callbackId];
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
            [self handleFatalError:errorMessage withCallbackId:latestCallbackId];
            [self removeBackgroundTask];
        }];
    }
}
@end
