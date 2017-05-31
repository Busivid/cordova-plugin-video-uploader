//
//  OneUploader.h
//
//  Created by Cory Thompson on 2017-06-16
//

#import <Cordova/CDV.h>

@interface OneUploader : CDVPlugin {
}

@property (nonatomic, assign) UIBackgroundTaskIdentifier backgroundTaskID;
@property (retain) CDVInvokedUrlCommand *command;
@property (copy) NSMutableArray *completedTransfers;
@property (retain) NSOperationQueue *transcodingQueue;
@property (retain) NSOperationQueue *uploadQueue;

- (void)applicationDidEnterBackground:(UIApplication *)application;
- (void)applicationWillEnterForeground:(UIApplication *)application;
- (void)cleanUp:(CDVInvokedUrlCommand*)command;
- (void)compressAndUpload:(CDVInvokedUrlCommand*)command;
@end
