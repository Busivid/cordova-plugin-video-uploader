#import "UploadOperationCommandDelegate.h"

@implementation UploadOperationCommandDelegate {
	CDVCommandDelegateImpl *commandDelegate;
	NSNumber *lastReportedProgress;
	NSNumber *offset;
	NSString *progressId;
	NSNumber *totalBytes;
}

@synthesize completionBlock;
@synthesize settings;
@synthesize urlTransformer;

- (void) evalJs:(NSString *)js {
	return [commandDelegate evalJs:js];
}

- (void) evalJs:(NSString *)js scheduledOnRunLoop:(BOOL)scheduledOnRunLoop {
	return [commandDelegate evalJs:js scheduledOnRunLoop:scheduledOnRunLoop];
}

- (id) getCommandInstance:(NSString *)pluginName {
	return [commandDelegate getCommandInstance:pluginName];
}

- (id) initWithCommandDelegateImpl:(CDVCommandDelegateImpl *) commandDelegateImpl progressId:(NSString *) pId offset:(NSNumber *) oBytes totalBytes:(NSNumber *) tBytes {
	commandDelegate = commandDelegateImpl;
	progressId = pId;
	offset = oBytes;
	totalBytes = tBytes;
	return [super init];
}

- (NSString *) pathForResource:(NSString *)resourcepath {
	return [commandDelegate pathForResource:resourcepath];
}

- (void) runInBackground:(void (^)())block {
	return [commandDelegate runInBackground:block];
}

- (void) sendPluginResult:(CDVPluginResult *)result callbackId:(NSString *)callbackId {
	NSDictionary *messages = (NSDictionary *) result.message;

	if ([messages objectForKey:@"lengthComputable"] == nil) {
		NSString *errorMessage;
		if ([result.status intValue] != CDVCommandStatus_OK)
			errorMessage = @"Error uploading file. Please check your internet connection and try again.";

		completionBlock(errorMessage);
		return;
	}

	NSNumber *totalBytesWritten = [NSNumber numberWithFloat:([messages[@"loaded"] floatValue] + [offset floatValue])];
	NSNumber *totalBytesExpectedToWrite = totalBytes;

	NSNumber *progress = [NSNumber numberWithFloat:floorf(100.0f * [totalBytesWritten floatValue] / [totalBytesExpectedToWrite floatValue])];

	if ([progress intValue] > [lastReportedProgress intValue]) {
		NSMutableDictionary *uploadProgress = [[NSMutableDictionary alloc] initWithCapacity:3];
		[uploadProgress setObject:progress forKey:@"progress"];
		[uploadProgress setObject:progressId forKey:@"progressId"];
		[uploadProgress setObject:@"PROGRESS_UPLOADING" forKey:@"type"];

		CDVPluginResult *newResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:uploadProgress];
		[newResult setKeepCallbackAsBool:true];

		[commandDelegate sendPluginResult:newResult callbackId:callbackId];
		lastReportedProgress = progress;
	}
}

- (void) setCompletionBlock:(void(^)(NSString *errorMessage))block {
	completionBlock = block;
}

- (NSString *) userAgent {
	return [commandDelegate userAgent];
}

@end
