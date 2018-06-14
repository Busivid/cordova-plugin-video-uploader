#import "AppDelegate_VideoUploader.h"
#import "BVVideoUploader.h"

@implementation AppDelegate (VideoUploader)

- (void) applicationDidEnterBackground:(UIApplication *) application {
	BVVideoUploader *uploader = [self.viewController getCommandInstance:@"VideoUploader"];
	[uploader applicationDidEnterBackground:application];
}

- (void) applicationWillEnterForeground:(UIApplication *) application {
	BVVideoUploader *uploader = [self.viewController getCommandInstance:@"VideoUploader"];
	[uploader applicationWillEnterForeground:application];
}
@end
