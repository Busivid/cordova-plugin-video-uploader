#import "UploadOperation.h"

#import "UploadOperationCommandDelegate.h";

@implementation UploadOperation
@synthesize commandDelegate;
@synthesize errorMessage;
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

- (id)initWithSource:(NSURL*)src target:(NSURL*)uploadTarget options:(NSDictionary *)opts commandDelegate:(id <CDVCommandDelegate>)cmdDelegate cordovaCallbackId:(NSString*)callbackId {
    if (![super init])
        return nil;
    
    cordovaCallbackId = callbackId;
    options = opts;
    
    fileTransfer = [[CDVFileTransfer alloc] init];
    [fileTransfer pluginInitialize];
    
    source = src;
    target = uploadTarget;
    
    return self;
}

- (void)main {
    if (self.isCancelled) {
        return;
    }
	
    //Order is important.
    NSMutableArray *args = [[NSMutableArray alloc] init];
    [args addObject:source.path];
    [args addObject:target.absoluteString];
    [args addObject:@"file"];
    [args addObject:@"test.mp4"];
    [args addObject:@"video/mp4"];
    [args addObject:options[@"params"]];
    [args addObject:[NSNumber numberWithInt:0]]	;
    [args addObject:[NSNumber numberWithInt:1]];
    [args addObject:[[NSDictionary alloc] init]];
    [args addObject:options[@"progressId"]];
    [args addObject:@"POST"];
    [args addObject:options[@"timeout"]];
    
    CDVInvokedUrlCommand* commandOptions = [[CDVInvokedUrlCommand alloc] initWithArguments:args callbackId:cordovaCallbackId className:@"CDVFileTransfer" methodName:@"upload"];
    dispatch_semaphore_t sessionWaitSemaphore = dispatch_semaphore_create(0);

    UploadOperationCommandDelegate* delegate = [[UploadOperationCommandDelegate alloc] initWithCommandDelegateImpl:commandDelegate withProgressId:options[@"progressId"]];
    [delegate setCompletionBlock:^(NSString* errorMsg){
        errorMessage = errorMsg;
        dispatch_semaphore_signal(sessionWaitSemaphore);
    }];
    [fileTransfer setCommandDelegate:delegate];
    
    [fileTransfer upload:commandOptions];
    dispatch_semaphore_wait(sessionWaitSemaphore, DISPATCH_TIME_FOREVER);
    
    if (errorMessage != nil)
        return;
    
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
