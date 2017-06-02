#import "CDVLocalFilesystem.h"
#import "UploadOperation.h"

#import <AssetsLibrary/ALAsset.h>
#import <AssetsLibrary/ALAssetRepresentation.h>
#import <AssetsLibrary/ALAssetsLibrary.h>
#import <CFNetwork/CFNetwork.h>
#import <Cordova/CDV.h>

#ifndef DLog
#ifdef DEBUG
#define DLog(fmt, ...) NSLog((@"%s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)
#else
#define DLog(...)
#endif
#endif

@interface UploadOperation ()
// Sets the requests headers for the request.
- (void)applyRequestHeaders:(NSDictionary*)headers toRequest:(NSMutableURLRequest*)req;
// Creates a delegate to handle an upload.
- (CDVFileTransferDelegate*)delegateForUploadCommand;
// Creates an NSData* for the file for the given upload arguments.
- (void)fileDataForUploadCommand;
@end

// Buffer size to use for streaming uploads.
static const NSUInteger kStreamBufferSize = 32768;
// Magic value within the options dict used to set a cookie.
NSString* const kOptionsKeyCookie = @"__cookie";
// Form boundary for multi-part requests.
NSString* const kFormBoundary = @"+++++org.apache.cordova.formBoundary";

// Writes the given data to the stream in a blocking way.
// If successful, returns bytesToWrite.
// If the stream was closed on the other end, returns 0.
// If there was an error, returns -1.
static CFIndex WriteDataToStream(NSData* data, CFWriteStreamRef stream)
{
    UInt8* bytes = (UInt8*)[data bytes];
    long long bytesToWrite = [data length];
    long long totalBytesWritten = 0;
    
    while (totalBytesWritten < bytesToWrite) {
        CFIndex result = CFWriteStreamWrite(stream,
                                            bytes + totalBytesWritten,
                                            bytesToWrite - totalBytesWritten);
        if (result < 0) {
            CFStreamError error = CFWriteStreamGetError(stream);
            NSLog(@"WriteStreamError domain: %ld error: %ld", error.domain, (long)error.error);
            return result;
        } else if (result == 0) {
            return result;
        }
        totalBytesWritten += result;
    }
    
    return totalBytesWritten;
}

@implementation UploadOperation
@synthesize activeTransfers;
@synthesize callbackId;
@synthesize commandDelegate;
@synthesize errorMessage;
@synthesize parameters;

- (void) main {
    if (self.isCancelled) {
        return;
    }
    
    [self upload];
    
    //Wait until file transfer is complete
    while ([activeTransfers objectForKey:self.parameters.progressId] != nil) {
        [NSThread sleepForTimeInterval:0.1f];
    }
}

- (void) cancel {
    [super cancel];
    
    @synchronized (activeTransfers) {
        while ([activeTransfers count] > 0) {
            CDVFileTransferDelegate* delegate = [activeTransfers allValues][0];
            [delegate cancelTransfer:delegate.connection];
        }
    }
}

- (id)init {
    if (![super init]) return nil;
    activeTransfers = [[NSMutableDictionary alloc] init];
    return self;
}

- (void)applyRequestHeaders:(NSDictionary*)headers toRequest:(NSMutableURLRequest*)req
{
    [req setValue:@"XMLHttpRequest" forHTTPHeaderField:@"X-Requested-With"];
    
    NSString* userAgent = [self.commandDelegate userAgent];
    if (userAgent) {
        [req setValue:userAgent forHTTPHeaderField:@"User-Agent"];
    }
    
    for (NSString* headerName in headers) {
        id value = [headers objectForKey:headerName];
        if (!value || (value == [NSNull null])) {
            value = @"null";
        }
        
        // First, remove an existing header if one exists.
        [req setValue:nil forHTTPHeaderField:headerName];
        
        if (![value isKindOfClass:[NSArray class]]) {
            value = [NSArray arrayWithObject:value];
        }
        
        // Then, append all header values.
        for (id __strong subValue in value) {
            // Convert from an NSNumber -> NSString.
            if ([subValue respondsToSelector:@selector(stringValue)]) {
                subValue = [subValue stringValue];
            }
            if ([subValue isKindOfClass:[NSString class]]) {
                [req addValue:subValue forHTTPHeaderField:headerName];
            }
        }
    }
}

- (NSURLRequest*)requestForFileData:(NSData*)fileData
{
    // NSURL does not accepts URLs with spaces in the path. We escape the path in order
    // to be more lenient.
    NSURL* url = [NSURL URLWithString:parameters.uploadUrl];
    NSString* httpMethod = @"POST";
    
    if (!url) {
        self.errorMessage = @"Invalid Server Url.";
    } else if (!fileData) {
        self.errorMessage = @"Local file could not be found.";
    }
    
    NSMutableURLRequest* req = [NSMutableURLRequest requestWithURL:url];
    [req setTimeoutInterval:[parameters.timeout doubleValue]];
    [req setHTTPMethod:httpMethod];
    
    /*//    Magic value to set a cookie
    if ([options objectForKey:kOptionsKeyCookie]) {
        [req setValue:[options objectForKey:kOptionsKeyCookie] forHTTPHeaderField:@"Cookie"];
        [req setHTTPShouldHandleCookies:NO];
    }*/
    
    // if we specified a Content-Type header, don't do multipart form upload
    BOOL multipartFormUpload = [parameters.headers objectForKey:@"Content-Type"] == nil;
    if (multipartFormUpload) {
        NSString* contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", kFormBoundary];
        [req setValue:contentType forHTTPHeaderField:@"Content-Type"];
    }
    [self applyRequestHeaders:parameters.headers toRequest:req];
    
    NSData* formBoundaryData = [[NSString stringWithFormat:@"--%@\r\n", kFormBoundary] dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData* postBodyBeforeFile = [NSMutableData data];
    
    // Cory: Not 100% sure if headers is correct for this?
    for (NSString* key in parameters.params) {
        id val = [parameters.params objectForKey:key];
        if (!val || (val == [NSNull null]) || [key isEqualToString:kOptionsKeyCookie]) {
            continue;
        }
        // if it responds to stringValue selector (eg NSNumber) get the NSString
        if ([val respondsToSelector:@selector(stringValue)]) {
            val = [val stringValue];
        }
        // finally, check whether it is a NSString (for dataUsingEncoding selector below)
        if (![val isKindOfClass:[NSString class]]) {
            continue;
        }
        
        [postBodyBeforeFile appendData:formBoundaryData];
        [postBodyBeforeFile appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n", key] dataUsingEncoding:NSUTF8StringEncoding]];
        [postBodyBeforeFile appendData:[val dataUsingEncoding:NSUTF8StringEncoding]];
        [postBodyBeforeFile appendData:[@"\r\n" dataUsingEncoding : NSUTF8StringEncoding]];
    }
    
    [postBodyBeforeFile appendData:formBoundaryData];
    [postBodyBeforeFile appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\n", parameters.fileKey, parameters.filePath] dataUsingEncoding:NSUTF8StringEncoding]];
    if (parameters.mimeType != nil) {
        [postBodyBeforeFile appendData:[[NSString stringWithFormat:@"Content-Type: %@\r\n", parameters.mimeType] dataUsingEncoding:NSUTF8StringEncoding]];
    }
    [postBodyBeforeFile appendData:[[NSString stringWithFormat:@"Content-Length: %ld\r\n\r\n", (long)[fileData length]] dataUsingEncoding:NSUTF8StringEncoding]];
    
    DLog(@"fileData length: %lu", (unsigned long)[fileData length]);
    NSData* postBodyAfterFile = [[NSString stringWithFormat:@"\r\n--%@--\r\n", kFormBoundary] dataUsingEncoding:NSUTF8StringEncoding];
    
    long long totalPayloadLength = [fileData length];
    if (multipartFormUpload) {
        totalPayloadLength += [postBodyBeforeFile length] + [postBodyAfterFile length];
    }
    
    [req setValue:[[NSNumber numberWithLongLong:totalPayloadLength] stringValue] forHTTPHeaderField:@"Content-Length"];
    
    if (parameters.chunkMode) {
        CFReadStreamRef readStream = NULL;
        CFWriteStreamRef writeStream = NULL;
        CFStreamCreateBoundPair(NULL, &readStream, &writeStream, kStreamBufferSize);
        [req setHTTPBodyStream:CFBridgingRelease(readStream)];
        [self.commandDelegate runInBackground:^{
        if (CFWriteStreamOpen(writeStream)) {
            if (multipartFormUpload) {
                NSData* chunks[] = { postBodyBeforeFile, fileData, postBodyAfterFile };
                int numChunks = sizeof(chunks) / sizeof(chunks[0]);
                    
                for (int i = 0; i < numChunks; ++i) {
                    // Allow uploading of an empty file
                    if (chunks[i].length == 0) {
                        continue;
                    }
                    //[NSThread sleepForTimeInterval:100];
                    CFIndex result = WriteDataToStream(chunks[i], writeStream);
                    if (result <= 0) {
                        break;
                    }
                }
            } else {
                WriteDataToStream(fileData, writeStream);
            }
        } else {
            NSLog(@"FileTransfer: Failed to open writeStream");
        }
        CFWriteStreamClose(writeStream);
        CFRelease(writeStream);
         }];
    } else {
        if (multipartFormUpload) {
            [postBodyBeforeFile appendData:fileData];
            [postBodyBeforeFile appendData:postBodyAfterFile];
            [req setHTTPBody:postBodyBeforeFile];
        } else {
            [req setHTTPBody:fileData];
        }
    }
    return req;
}

- (CDVFileTransferDelegate*)delegateForUploadCommand
{
    CDVFileTransferDelegate* delegate = [[CDVFileTransferDelegate alloc] init];
    
    delegate.command = self;
    delegate.callbackId = callbackId;
    delegate.callbackUrl = parameters.callbackUrl;
    delegate.source = parameters.filePath;
    delegate.target = parameters.uploadUrl;
    delegate.trustAllHosts = false;
    delegate.filePlugin = [self.commandDelegate getCommandInstance:@"File"];
    delegate.progressId = parameters.progressId;
    
    return delegate;
}

- (void)fileDataForUploadCommand{
    NSError* __autoreleasing err = nil;
    
    if ([parameters.filePath hasPrefix:@"data:"] && [parameters.filePath rangeOfString:@"base64"].location != NSNotFound) {
        NSRange commaRange = [parameters.filePath rangeOfString: @","];
        if (commaRange.location == NSNotFound) {
            // Return error is there is no comma
            self.errorMessage = @"Invalid URL";
            return;
        }
        
        if (commaRange.location + 1 > parameters.filePath.length - 1) {
            // Init as an empty data
            NSData *fileData = [[NSData alloc] init];
            [self uploadData:fileData];
            return;
        }
        
        NSData *fileData = [[NSData alloc] initWithBase64EncodedString:[parameters.filePath substringFromIndex:(commaRange.location + 1)] options:NSDataBase64DecodingIgnoreUnknownCharacters];
        [self uploadData:fileData];
        return;
    }
    
    CDVFilesystemURL *sourceURL = [CDVFilesystemURL fileSystemURLWithString:parameters.filePath];
    NSObject<CDVFileSystem> *fs;
    if (sourceURL) {
        // Try to get a CDVFileSystem which will handle this file.
        // This requires talking to the current CDVFile plugin.
        fs = [[self.commandDelegate getCommandInstance:@"File"] filesystemForURL:sourceURL];
    }
    if (fs) {
        __weak UploadOperation* weakSelf = self;
        [fs readFileAtURL:sourceURL start:0 end:-1 callback:^(NSData *fileData, NSString *mimeType, CDVFileError err) {
            if (err) {
            	self.errorMessage = @"Could not find local file for upload.";
            }  else {
                [weakSelf uploadData:fileData];
            }
        }];
        return;
    } else {
        // Extract the path part out of a file: URL.
        NSString* filePath = [parameters.filePath hasPrefix:@"/"] ? [parameters.filePath copy] : [(NSURL *)[NSURL URLWithString:parameters.filePath] path];
        if (filePath == nil) {
            // We couldn't find the asset.  Send the appropriate error.
            self.errorMessage = @"Could not find local file for upload.";
            return;
        }
        
        // Memory map the file so that it can be read efficiently even if it is large.
        NSData* fileData = [NSData dataWithContentsOfFile:filePath options:NSDataReadingMappedIfSafe error:&err];
        
        if (err != nil) {
            self.errorMessage = @"Could not find local file for upload.";
        } else {
            [self uploadData:fileData];
        }
    }
}

- (void)upload
{
    // fileData and req are split into helper functions to ease the unit testing of delegateForUpload.
    // First, get the file data.  This method will call `uploadData:command`.
    [self fileDataForUploadCommand];
}

- (void)uploadData:(NSData*)fileData {
    NSURLRequest* req = [self requestForFileData:fileData];
    
    if (req == nil) {
        return;
    }
    CDVFileTransferDelegate* delegate = [self delegateForUploadCommand];
    delegate.connection = [[NSURLConnection alloc] initWithRequest:req delegate:delegate startImmediately:NO];
    if (self.queue == nil) {
        self.queue = [[NSOperationQueue alloc] init];
    }
    [delegate.connection setDelegateQueue:self.queue];
    
    @synchronized (activeTransfers) {
        activeTransfers[delegate.progressId] = delegate;
    }
    [delegate.connection start];
}

- (NSMutableDictionary*)createFileTransferError:(int)code AndSource:(NSString*)source AndTarget:(NSString*)target
{
    NSMutableDictionary* result = [NSMutableDictionary dictionaryWithCapacity:3];
    
    [result setObject:[NSNumber numberWithInt:code] forKey:@"code"];
    if (source != nil) {
        [result setObject:source forKey:@"source"];
    }
    if (target != nil) {
        [result setObject:target forKey:@"target"];
    }
    NSLog(@"FileTransferError %@", result);
    
    return result;
}

- (NSMutableDictionary*)createFileTransferError:(int)code
                                      AndSource:(NSString*)source
                                      AndTarget:(NSString*)target
                                  AndHttpStatus:(int)httpStatus
                                        AndBody:(NSString*)body
{
    NSMutableDictionary* result = [NSMutableDictionary dictionaryWithCapacity:5];
    
    [result setObject:[NSNumber numberWithInt:code] forKey:@"code"];
    if (source != nil) {
        [result setObject:source forKey:@"source"];
    }
    if (target != nil) {
        [result setObject:target forKey:@"target"];
    }
    [result setObject:[NSNumber numberWithInt:httpStatus] forKey:@"http_status"];
    if (body != nil) {
        [result setObject:body forKey:@"body"];
    }
    NSLog(@"FileTransferError %@", result);
    
    return result;
}

- (void)onReset {
    @synchronized (activeTransfers) {
        while ([activeTransfers count] > 0) {
            CDVFileTransferDelegate* delegate = [activeTransfers allValues][0];
            [delegate cancelTransfer:delegate.connection];
        }
    }
}

@end

@interface CDVFileTransferEntityLengthRequest : NSObject {
    NSURLConnection* _connection;
    CDVFileTransferDelegate* __weak _originalDelegate;
}

- (CDVFileTransferEntityLengthRequest*)initWithOriginalRequest:(NSURLRequest*)originalRequest andDelegate:(CDVFileTransferDelegate*)originalDelegate;

@end

@implementation CDVFileTransferEntityLengthRequest

- (CDVFileTransferEntityLengthRequest*)initWithOriginalRequest:(NSURLRequest*)originalRequest andDelegate:(CDVFileTransferDelegate*)originalDelegate
{
    if (self) {
        DLog(@"Requesting entity length for GZIPped content...");
        
        NSMutableURLRequest* req = [originalRequest mutableCopy];
        [req setHTTPMethod:@"HEAD"];
        [req setValue:@"identity" forHTTPHeaderField:@"Accept-Encoding"];
        
        _originalDelegate = originalDelegate;
        _connection = [NSURLConnection connectionWithRequest:req delegate:self];
    }
    return self;
}

- (void)connection:(NSURL*)connection didReceiveResponse:(NSURLResponse*)response
{
    DLog(@"HEAD request returned; content-length is %lld", [response expectedContentLength]);
    [_originalDelegate updateBytesExpected:[response expectedContentLength]];
}

- (void)connection:(NSURLConnection*)connection didReceiveData:(NSData*)data
{}

- (void)connectionDidFinishLoading:(NSURLConnection*)connection
{}

@end

@implementation CDVFileTransferDelegate

@synthesize callbackId, connection = _connection, source, target, responseData, responseHeaders, command, bytesTransfered, bytesExpected, responseCode, targetFileHandle, filePlugin, lastReportedProgress, progressId;

- (void)connectionDidFinishLoading:(NSURLConnection*)connection
{
    NSString* uploadResponse = nil;
    NSMutableDictionary* uploadResult;
    
    NSLog(@"File Transfer Finished with response code %d", self.responseCode);
    
    uploadResponse = [[NSString alloc] initWithData:self.responseData encoding:NSUTF8StringEncoding];
    if (uploadResponse == nil) {
        uploadResponse = [[NSString alloc] initWithData: self.responseData encoding:NSISOLatin1StringEncoding];
    }
        
    if ((self.responseCode >= 200) && (self.responseCode < 300)) {
        // create dictionary to return FileUploadResult object
        uploadResult = [NSMutableDictionary dictionaryWithCapacity:3];
        if (uploadResponse != nil) {
            [uploadResult setObject:uploadResponse forKey:@"response"];
            [uploadResult setObject:self.responseHeaders forKey:@"headers"];
        }
        [uploadResult setObject:[NSNumber numberWithLongLong:self.bytesTransfered] forKey:@"bytesSent"];
        [uploadResult setObject:[NSNumber numberWithInt:self.responseCode] forKey:@"responseCode"];
    } else {
        self.command.errorMessage = @"Connection error while uploading your file.";
    }

    if (self.callbackUrl && self.responseCode >= 200 && self.responseCode < 300) {
        bool shouldRetry;
        do {
            shouldRetry = false;
            
            NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
            [request setHTTPMethod:@"GET"];
            [request setURL:[NSURL URLWithString:self.callbackUrl]];
            
            NSError *error = nil;
            NSHTTPURLResponse *callbackResponseCode = nil;
            
            NSData *oResponseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&callbackResponseCode error:&error];
            
            // response code of the callback, not of the upload.
            if ([callbackResponseCode statusCode] == 503) {
                //maintenance mode.
                shouldRetry = true;
                [NSThread sleepForTimeInterval: 10.0f];
            } else if ([callbackResponseCode statusCode] != 200) {
                [self cancelTransferWithError:connection errorMessage:@"Sorry, this action cannot be performed at this time. Please try again later."];
                return;
            }
        } while (shouldRetry);
    }
    
    
    // remove connection for activeTransfers
    @synchronized (command.activeTransfers) {
        [command.activeTransfers removeObjectForKey:progressId];
    }
}

- (void)cancelTransfer:(NSURLConnection*)connection
{
    [connection cancel];
    @synchronized (self.command.activeTransfers) {
        [self.command.activeTransfers removeObjectForKey:self.progressId];
    }
}

- (void)cancelTransferWithError:(NSURLConnection*)connection errorMessage:(NSString*)errorMessage
{
    self.command.errorMessage = errorMessage;
    NSLog(@"File Transfer Error: %@", errorMessage);
    [self cancelTransfer:connection];
}

- (void)connection:(NSURLConnection*)connection didReceiveResponse:(NSURLResponse*)response
{
    self.mimeType = [response MIMEType];
    self.targetFileHandle = nil;
    
    // required for iOS 4.3, for some reason; response is
    // a plain NSURLResponse, not the HTTP subclass
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;

        self.responseCode = (int)[httpResponse statusCode];
        self.bytesExpected = [response expectedContentLength];
        self.responseHeaders = [httpResponse allHeaderFields];
    } else if ([response.URL isFileURL]) {
        NSDictionary* attr = [[NSFileManager defaultManager] attributesOfItemAtPath:[response.URL path] error:nil];
        self.responseCode = 200;
        self.bytesExpected = [attr[NSFileSize] longLongValue];
    } else {
        self.responseCode = 200;
        self.bytesExpected = NSURLResponseUnknownLength;
    }
}

- (void)connection:(NSURLConnection*)connection didFailWithError:(NSError*)error
{
    self.command.errorMessage = [error localizedDescription];
    NSLog(@"File Transfer Error: %@", [error localizedDescription]);
    
    [self cancelTransfer:connection];
}

- (void)connection:(NSURLConnection*)connection didReceiveData:(NSData*)data
{
    self.bytesTransfered += data.length;
    if (self.targetFileHandle) {
        [self.targetFileHandle writeData:data];
    } else {
        [self.responseData appendData:data];
    }
}

- (void)updateBytesExpected:(long long)newBytesExpected
{
    DLog(@"Updating bytesExpected to %lld", newBytesExpected);
    self.bytesExpected = newBytesExpected;
}

- (void)connection:(NSURLConnection*)connection didSendBodyData:(NSInteger)bytesWritten totalBytesWritten:(NSInteger)totalBytesWritten totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite
{
    
    NSNumber* progress = [NSNumber numberWithFloat:floorf(100.0f * totalBytesWritten / totalBytesExpectedToWrite)];
    if (progress > lastReportedProgress) {
    	NSMutableDictionary* uploadProgress = [NSMutableDictionary dictionaryWithCapacity:1];
    	NSLog(@"File transfer progress (%@) %3.0f%%", self.progressId, [progress floatValue]);

    	[uploadProgress setObject:progress forKey:@"progress"];
        [uploadProgress setObject:progressId forKey:@"progressId"];
        [uploadProgress setObject:@"UPLOADING" forKey:@"type"];

    	CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:uploadProgress];
		[result setKeepCallbackAsBool:true];
    	[self.command.commandDelegate sendPluginResult:result callbackId:callbackId];
        
        lastReportedProgress = progress;
    }
    
    self.bytesTransfered = totalBytesWritten;
}

@end

@implementation UploadParameters
@end
