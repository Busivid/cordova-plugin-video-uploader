#import "UploadOperationCommandDelegate.h"

@implementation UploadOperationCommandDelegate
@synthesize completionBlock;
@synthesize settings;
@synthesize urlTransformer;

- (id)initWithCommandDelegateImpl:(CDVCommandDelegateImpl*)commandDelegateImpl withProgressId:(NSString*)pId {
    commandDelegate = commandDelegateImpl;
    progressId = pId;
    return [super init];
}

- (void)setCompletionBlock:(void(^)(NSString* errorMessage))block {
    completionBlock = block;
}

- (NSString*)pathForResource:(NSString*)resourcepath {
    return [commandDelegate pathForResource:resourcepath];
}

- (id)getCommandInstance:(NSString*)pluginName {
    return [commandDelegate getCommandInstance:pluginName];
}

- (void)sendPluginResult:(CDVPluginResult*)result callbackId:(NSString*)callbackId {
    NSDictionary* messages = (NSDictionary*)result.message;
    
    if ([messages objectForKey:@"lengthComputable"] == nil) {
        NSString* errorMessage;
        if ([result.status intValue] != CDVCommandStatus_OK) {
            errorMessage = @"Error uploading file. Please check your internet connection and try again.";
        }
        
        completionBlock(errorMessage);
        return;
    }

    NSNumber* totalBytesWritten = messages[@"loaded"];
    NSNumber* totalBytesExpectedToWrite = messages[@"total"];
    
    NSNumber* progress = [NSNumber numberWithFloat:floorf(100.0f * [totalBytesWritten floatValue] / [totalBytesExpectedToWrite floatValue])];
    
    if ([progress intValue] > [lastReportedProgress intValue]) {
    	NSMutableDictionary* uploadProgress = [[NSMutableDictionary alloc] initWithCapacity:3];
    	[uploadProgress setObject:progress forKey:@"progress"];
    	[uploadProgress setObject:progressId forKey:@"progressId"];
    	[uploadProgress setObject:@"UPLOADING" forKey:@"type"];
        
        
        CDVPluginResult* newResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:uploadProgress];
        [newResult setKeepCallbackAsBool:true];

        [commandDelegate sendPluginResult:newResult callbackId:callbackId];
        lastReportedProgress = progress;
    }
}

// Evaluates the given JS. This is thread-safe.
- (void)evalJs:(NSString*)js {
    return [commandDelegate evalJs:js];
}

- (void)evalJs:(NSString*)js scheduledOnRunLoop:(BOOL)scheduledOnRunLoop {
    return [commandDelegate evalJs:js scheduledOnRunLoop:scheduledOnRunLoop];
}

- (void)runInBackground:(void (^)())block {
    return [commandDelegate runInBackground:block];
}

- (NSString*)userAgent {
    return [commandDelegate userAgent];
}

@end
