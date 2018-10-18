#import "AppDelegate.h"
#import <Availability.h>
#import <PushKit/PushKit.h>

UIBackgroundTaskIdentifier bgTask;

@interface AppDelegate (VoIPPushNotification)

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions;
- (void)endBackgroundTask;

@property (nonatomic) UIBackgroundTaskIdentifier bgTask;

@end