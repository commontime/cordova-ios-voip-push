#import "AppDelegate+VoIPPushNotification.h"

@implementation AppDelegate (VoIPPushNotification)

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    UIApplication* app = [UIApplication sharedApplication];
    bgTask = [app beginBackgroundTaskWithExpirationHandler:^{
        [app endBackgroundTask:bgTask];
        bgTask = UIBackgroundTaskInvalid;
    }];
    return [super application:application didFinishLaunchingWithOptions:launchOptions];
};

- (void)endBackgroundTask {
    UIApplication* app = [UIApplication sharedApplication];
    [app endBackgroundTask:bgTask];
}

@dynamic bgTask;

@end