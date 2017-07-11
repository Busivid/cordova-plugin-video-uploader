//
//  VideoUploader.h
//
//  Created by Cory Thompson on 2017-06-16
//

#import <Cordova/CDV.h>

@interface VideoUploader : CDVPlugin {
    UIBackgroundTaskIdentifier backgroundTaskID;
    NSString *latestCallbackId;
    NSOperationQueue *transcodingQueue;
    NSOperationQueue *uploadQueue;
}

@property (copy) NSMutableArray *completedTransfers;

- (void)abort:(CDVInvokedUrlCommand*)command;
- (void)applicationDidEnterBackground:(UIApplication *)application;
- (void)applicationWillEnterForeground:(UIApplication *)application;
- (void)cleanUp:(CDVInvokedUrlCommand*)command;
- (void)compressAndUpload:(CDVInvokedUrlCommand*)command;
@end
