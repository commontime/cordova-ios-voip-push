#import "AppDelegate+VoIPPushNotification.h"

@implementation AppDelegate (VoIPPushNotification)

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    UIApplication* app = [UIApplication sharedApplication];
    self.bgTask = [app beginBackgroundTaskWithExpirationHandler:^{
        [app endBackgroundTask:self.bgTask];
        self.bgTask = UIBackgroundTaskInvalid;
    }];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        while (true) {
            ;
        }
    });
    PKPushRegistry *pushRegistry =
    [[PKPushRegistry alloc] initWithQueue:dispatch_get_main_queue()];
    pushRegistry.delegate = self;
    pushRegistry.desiredPushTypes = [NSSet setWithObject:PKPushTypeVoIP];
    return YES;
};

- (void)pushRegistry:(PKPushRegistry *)registry didUpdatePushCredentials:(PKPushCredentials *)credentials forType:(NSString *)type {
    UIApplication* app = [UIApplication sharedApplication];
    [app endBackgroundTask:self.bgTask];
}

@end