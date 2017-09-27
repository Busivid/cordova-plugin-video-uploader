#import "AppDelegate+uploader.h"
#import "VideoUploader.h"

@implementation AppDelegate (uploader)
- (id) getCommandInstance:(NSString*)className
{
	return [self.viewController getCommandInstance:className];
}

- (void) applicationDidEnterBackground:(UIApplication *) application {
	VideoUploader *uploader = [self getCommandInstance:@"VideoUploader"];
	[uploader applicationDidEnterBackground:application];
}

- (void) applicationWillEnterForeground:(UIApplication *) application {
	VideoUploader *uploader = [self getCommandInstance:@"VideoUploader"];
	[uploader applicationWillEnterForeground:application];
}
@end
