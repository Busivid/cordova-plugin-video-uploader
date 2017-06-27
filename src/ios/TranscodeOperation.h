#import <Cordova/CDV.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@interface TranscodeOperation : NSOperation {
    Float64 maxSeconds;

    NSURL *dstPath;
    NSURL *srcPath;

    id <CDVCommandDelegate> __weak commandDelegate;
    NSString *callbackId;
}

@property Float64 maxSeconds;

@property(retain) NSString *callbackId;
@property(retain) NSString *progressId;
@property(retain) NSURL *dstPath;
@property(retain) NSURL *srcPath;
@property(retain) NSString *errorMessage;
@property(retain) NSNumber *fileLengthLimit;

@property(retain) AVAssetExportSession *exportSession;

@property (nonatomic, weak) id <CDVCommandDelegate> commandDelegate;

- (id)initWithSrc:(NSURL *)src dst:(NSURL*)dst maxSeconds:(Float64)seconds fileLengthLimit:(NSNumber*)lengthLimit progressId:(NSString*)pId;

@end
