//
//  Created by Cory Thompson on 2017-06-16
//

#import <Cordova/CDV.h>

@interface BVVideoUploader : CDVPlugin

@property (readonly) NSMutableArray *completedUploads;

- (void) abort:(CDVInvokedUrlCommand *)command;
- (void) applicationDidEnterBackground:(UIApplication *)application;
- (void) applicationWillEnterForeground:(UIApplication *)application;
- (void) cleanUp:(CDVInvokedUrlCommand *)command;
- (void) compressAndUpload:(CDVInvokedUrlCommand *)command;

@end
