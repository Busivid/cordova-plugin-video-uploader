#import "UploadOperation.h"
#import "UploadOperationCommandDelegate.h"

@implementation UploadOperation {
	NSMutableDictionary *_uploadCompleteUrlFields;
}

@synthesize errorMessage;
@synthesize source;
@synthesize target;
@synthesize uploadCompleteUrl;
@synthesize uploadCompleteUrlAuthorization;
@synthesize uploadCompleteUrlMethod;

- (void) addUploadCompleteUrlFields:(NSDictionary *) dict {
	[_uploadCompleteUrlFields addEntriesFromDictionary:dict];
}

- (void) cancel {
	[super cancel];

	// Call abort on current file transfer
	if (fileTransfer != nil) {
		NSMutableArray *args = [[NSMutableArray alloc] init];
		[args addObject:options[@"progressId"]];

		CDVInvokedUrlCommand *commandOptions = [[CDVInvokedUrlCommand alloc] initWithArguments:args callbackId:cordovaCallbackId className:@"CDVFileTransfer" methodName:@"abort"];
		[fileTransfer abort:commandOptions];
	}
}

- (bool) doesFileExistsAtUrl:(NSURL*) url {
	NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
	[request setHTTPMethod:@"HEAD"];
	[request setURL:url];

	NSError *error = nil;
	NSHTTPURLResponse *callbackResponseCode = nil;

	NSData *oResponseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&callbackResponseCode error:&error];
	return [callbackResponseCode statusCode] == 200;
}

- (id) initWithOptions:(NSDictionary *) opts commandDelegate:(id <CDVCommandDelegate>) cmdDelegate cordovaCallbackId:(NSString*) callbackId {
	if (![super init])
		return nil;

	cordovaCallbackId = callbackId;
	commandDelegate = cmdDelegate;
	options = opts;

	fileTransfer = [[CDVFileTransfer alloc] init];
	[fileTransfer pluginInitialize];

	_uploadCompleteUrlFields = [[NSMutableDictionary alloc] init];

	return self;
}

- (void) main {
	if (self.isCancelled)
		return;

	if (source == nil || target == nil) {
		self.errorMessage = @"Source and target must be defined.";
		return;
	}

	unsigned long long fileSize = [[[NSFileManager defaultManager] attributesOfItemAtPath:source.path error:nil] fileSize];
	NSString *fileName = [[source path] lastPathComponent];

	int chunkSize = [options[@"chunkSize"] intValue];
	int requiredChunkCount = chunkSize <= 0
		? 1
		: ceil(fileSize / (float)chunkSize);

	NSDate *uploadStartTime = [NSDate date];
	for(int chunkNumber = 0; chunkNumber < requiredChunkCount; chunkNumber++) {
		NSNumber *offset = [NSNumber numberWithInt:chunkSize * chunkNumber];

		NSDictionary *headers = options[@"headers"] == nil
			? [[NSDictionary alloc] init]
			: options[@"headers"];

		NSDictionary *params = options[@"params"] == nil || options[@"params"][chunkNumber] == nil
			? [[NSDictionary alloc] init]
			: options[@"params"][chunkNumber];

		NSURL *expectedFileUrl = [target URLByAppendingPathComponent:params[@"key"]];
		bool isFileAlreadyUploaded = [self doesFileExistsAtUrl:expectedFileUrl];
		if(isFileAlreadyUploaded) {
			uploadStartTime = nil;
			continue;
		}

		//Order is important.
		NSMutableArray *args = [[NSMutableArray alloc] init];
		[args addObject:source.path];
		[args addObject:target.absoluteString];
		[args addObject:@"file"];
		[args addObject:fileName];
		[args addObject:@"video/mp4"];
		[args addObject:params];
		[args addObject:[NSNumber numberWithInt:0]]	;
		[args addObject:[NSNumber numberWithInt:1]];
		[args addObject:headers];
		[args addObject:options[@"progressId"]];
		[args addObject:@"POST"];
		[args addObject:options[@"timeout"]];
		[args addObject:offset];
		[args addObject:[NSNumber numberWithInt:chunkSize]];

		CDVInvokedUrlCommand* commandOptions = [[CDVInvokedUrlCommand alloc] initWithArguments:args callbackId:cordovaCallbackId className:@"CDVFileTransfer" methodName:@"upload"];
		dispatch_semaphore_t sessionWaitSemaphore = dispatch_semaphore_create(0);

		UploadOperationCommandDelegate* delegate = [[UploadOperationCommandDelegate alloc] initWithCommandDelegateImpl:commandDelegate progressId:options[@"progressId"] offset:offset totalBytes:[NSNumber numberWithLong:fileSize]];
		[delegate setCompletionBlock:^(NSString* errorMsg){
			errorMessage = errorMsg;
			dispatch_semaphore_signal(sessionWaitSemaphore);
		}];
		[fileTransfer setCommandDelegate:delegate];

		// Auto-release pool required to let go of internal fileData object.
		@autoreleasepool {
			[fileTransfer upload:commandOptions];
			dispatch_semaphore_wait(sessionWaitSemaphore, DISPATCH_TIME_FOREVER);
		}

		if (errorMessage != nil)
			return;

		if (self.isCancelled)
			return;
	}

	NSTimeInterval clientUploadSeconds = uploadStartTime == nil
		? -1
		: [[NSDate date] timeIntervalSinceDate: uploadStartTime];

	[self onUploadComplete: clientUploadSeconds];
}

- (void) onUploadComplete: (NSTimeInterval) clientUploadSeconds {
	if (uploadCompleteUrl == nil)
		return;

	while (true) {
		NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
		[request setHTTPMethod:uploadCompleteUrlMethod];
		[request setURL:uploadCompleteUrl];

		if (uploadCompleteUrlAuthorization != nil) {
			[request setValue:uploadCompleteUrlAuthorization forHTTPHeaderField:@"Authorization"];
		}

		if (clientUploadSeconds >= 0) {
			if ([uploadCompleteUrlMethod isEqualToString:@"GET"]) {
				// Add parameters to URL
				NSURLComponents *url = [[NSURLComponents alloc] initWithURL:request.URL resolvingAgainstBaseURL:YES];
				NSArray<NSURLQueryItem*> *queryItems = [url queryItems];

				NSURLQueryItem *queryItem = [NSURLQueryItem queryItemWithName: @"ClientUploadSeconds" value: [@(ceil(clientUploadSeconds)) stringValue]];
				queryItems = [queryItems arrayByAddingObject: queryItem];

				[url setQueryItems: queryItems];
				[request setURL:url.URL];
			} else if ([uploadCompleteUrlMethod isEqualToString:@"POST"] || [uploadCompleteUrlMethod isEqualToString:@"PUT"]) {
				[_uploadCompleteUrlFields setObject:[@(ceil(clientUploadSeconds)) stringValue] forKey:@"ClientUploadSeconds"];
			}
		}

		if ([uploadCompleteUrlMethod isEqualToString:@"POST"] || [uploadCompleteUrlMethod isEqualToString:@"PUT"]) {
			NSError *jsonError = nil;
			NSData *jsonData = [NSJSONSerialization dataWithJSONObject:_uploadCompleteUrlFields options:NSJSONWritingPrettyPrinted error:&jsonError];
			if (!jsonData) {
				NSLog(@"Got an error: %@", jsonError);
				return;
			}

			NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
			NSData *requestData = [NSData dataWithBytes:[jsonString UTF8String] length:[jsonString lengthOfBytesUsingEncoding:NSUTF8StringEncoding]];

			[request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
			[request setValue:@"application/json; charset=UTF-8" forHTTPHeaderField:@"Content-Type"];
			[request setValue:[NSString stringWithFormat:@"%lu", (unsigned long)[requestData length]] forHTTPHeaderField:@"Content-Length"];
			[request setHTTPBody: requestData];
		}

		NSError *error = nil;
		NSHTTPURLResponse *callbackResponseCode = nil;
		NSData *oResponseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&callbackResponseCode error:&error];

		if ([callbackResponseCode statusCode] == 503) {
			[NSThread sleepForTimeInterval: 10.0f];
			continue;
		}

		if ([callbackResponseCode statusCode] != 200)
			self.errorMessage = @"Sorry, this action cannot be performed at this time. Please try again later.";

		return;
	}
}
@end
