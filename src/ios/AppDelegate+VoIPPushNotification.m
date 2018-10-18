#import "AppDelegate+VoIPPushNotification.h"

@implementation AppDelegate (VoIPPushNotification)

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    UIApplication* app = [UIApplication sharedApplication];
    bgTask = [app beginBackgroundTaskWithExpirationHandler:^{
        [app endBackgroundTask:bgTask];
        bgTask = UIBackgroundTaskInvalid;
    }];
    PKPushRegistry *pushRegistry = [[PKPushRegistry alloc] initWithQueue:dispatch_get_main_queue()];
    pushRegistry.delegate = self;
    pushRegistry.desiredPushTypes = [NSSet setWithObject:PKPushTypeVoIP];
    return [super application:application didFinishLaunchingWithOptions:launchOptions];
};

- (void)endBackgroundTask {
    UIApplication* app = [UIApplication sharedApplication];
    [app endBackgroundTask:bgTask];
}

@dynamic bgTask;

@end