#import "AppDelegate+uploader.h"
#import "OneUploader.h"

@implementation AppDelegate (uploader)
- (id) getCommandInstance:(NSString*)className
{
    return [self.viewController getCommandInstance:className];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    OneUploader *oneUploader = [self getCommandInstance:@"OneUploader"];
    [oneUploader applicationDidEnterBackground:application];
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    OneUploader *oneUploader = [self getCommandInstance:@"OneUploader"];
    [oneUploader applicationWillEnterForeground:application];
}
@end
