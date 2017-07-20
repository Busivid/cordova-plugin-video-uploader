#import "UploadOperation.h"
#import "UploadOperationCommandDelegate.h"

@implementation UploadOperation
@synthesize errorMessage;
@synthesize source;
@synthesize target;
@synthesize uploadCompleteUrl;

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

- (id)initWithOptions:(NSDictionary *)opts commandDelegate:(id <CDVCommandDelegate>)cmdDelegate cordovaCallbackId:(NSString*)callbackId {
    if (![super init])
        return nil;
    
    cordovaCallbackId = callbackId;
    commandDelegate = cmdDelegate;
    options = opts;
    
    fileTransfer = [[CDVFileTransfer alloc] init];
    [fileTransfer pluginInitialize];
    
    return self;
}

- (void)main {
    if (self.isCancelled) {
        return;
    }
    
    if (source == nil || target == nil) {
        self.errorMessage = @"Source and target must be defined.";
        return;
    }

    int chunkSize = [options[@"chunkSize"] intValue];
    unsigned long long fileSize = [[[NSFileManager defaultManager] attributesOfItemAtPath:source.path error:nil] fileSize];
    NSString *fileName = [[source path] lastPathComponent];

    int requiredChunkCount = ceil(fileSize / (float)chunkSize);
    for(int chunkNumber = 0; chunkNumber < requiredChunkCount; chunkNumber++) {
        NSNumber *offset = [NSNumber numberWithInt:chunkSize * chunkNumber];
        
        NSDictionary *headers = options[@"headers"] == nil
        	? [[NSDictionary alloc] init]
        	: options[@"headers"];
        
        //Order is important.
        NSMutableArray *args = [[NSMutableArray alloc] init];
        [args addObject:source.path];
        [args addObject:target.absoluteString];
        [args addObject:@"file"];
        [args addObject:fileName];
        [args addObject:@"video/mp4"];
        [args addObject:options[@"params"][chunkNumber]];
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
	
	if (uploadCompleteUrl != nil) {
        bool shouldRetry;
        do {
            shouldRetry = false;
            
            NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
            [request setHTTPMethod:@"GET"];
            [request setURL:uploadCompleteUrl];
            
            NSError *error = nil;
            NSHTTPURLResponse *callbackResponseCode = nil;
            
            NSData *oResponseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&callbackResponseCode error:&error];
            
            // response code of the callback, not of the upload.
            if ([callbackResponseCode statusCode] == 503) {
                //maintenance mode.
                shouldRetry = true;
                [NSThread sleepForTimeInterval: 10.0f];
            } else if ([callbackResponseCode statusCode] != 200) {
                self.errorMessage = @"Sorry, this action cannot be performed at this time. Please try again later.";
                return;
            }
        } while (shouldRetry);
    }
}
@end
