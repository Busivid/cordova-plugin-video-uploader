#import <Cordova/CDV.h>
#import "CDVFile.h"


@interface UploadParameters: NSObject {}
@property (nonatomic, copy) NSString* callbackUrl;
@property (nonatomic, assign) BOOL chunkMode;
@property (nonatomic, copy) NSString* fileKey;
@property (nonatomic, copy) NSString* fileName;
@property (nonatomic, strong) NSDictionary* headers;
@property (nonatomic, copy) NSString* mimeType;
@property (nonatomic, copy) NSNumber* timeout;
@property (nonatomic, copy) NSString* filePath;
@property (nonatomic, copy) NSString* uploadUrl;
@property (nonatomic, copy) NSString* progressId;
@end

@interface UploadOperation : NSOperation {
    id <CDVCommandDelegate> __weak commandDelegate;
    NSString *callbackId;
}

enum CDVFileTransferError {
    FILE_NOT_FOUND_ERR = 1,
    INVALID_URL_ERR = 2,
    CONNECTION_ERR = 3,
    CONNECTION_ABORTED = 4,
    NOT_MODIFIED = 5
};
typedef int CDVFileTransferError;

// Magic value within the options dict used to set a cookie.
extern NSString* const kOptionsKeyCookie;
@property (readonly) NSMutableDictionary* activeTransfers;
@property(retain) NSString *callbackId;
@property (nonatomic, weak) id <CDVCommandDelegate> commandDelegate;
@property (nonatomic, strong) NSOperationQueue* queue;
@property (nonatomic, strong) UploadParameters* parameters;
@property (nonatomic, copy) NSString* errorMessage;

- (id)init;
- (void)main;
@end

@class CDVFileTransferEntityLengthRequest;
@interface CDVFileTransferDelegate : NSObject {}
- (void)updateBytesExpected:(long long)newBytesExpected;
- (void)cancelTransfer:(NSURLConnection*)connection;

@property (strong) NSMutableData* responseData; // atomic
@property (nonatomic, strong) NSDictionary* responseHeaders;
@property (nonatomic, strong) UploadOperation* command;
@property (nonatomic, strong) NSURLConnection* connection;
@property (nonatomic, copy) NSString* callbackId;
@property (nonatomic, copy) NSString* callbackUrl;
@property (nonatomic, copy) NSString* source;
@property (nonatomic, copy) NSString* target;
@property (nonatomic, copy) NSURL* targetURL;
@property (nonatomic, copy) NSString* mimeType;
@property (assign) int responseCode; // atomic
@property (nonatomic, assign) long long bytesTransfered;
@property (nonatomic, assign) long long bytesExpected;
@property (nonatomic, assign) BOOL trustAllHosts;
@property (strong) NSFileHandle* targetFileHandle;
@property (nonatomic, strong) CDVFileTransferEntityLengthRequest* entityLengthRequest;
@property (nonatomic, strong) CDVFile *filePlugin;
@property (nonatomic, assign) BOOL chunkedMode;
@property (nonatomic, copy) NSNumber* lastReportedProgress;
@property (nonatomic, copy) NSString* progressId;
@end
