#import "AppDelegate.h"
#import <Availability.h>
#import <PushKit/PushKit.h>

@interface AppDelegate (VoIPPushNotification)

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions;
- (void)pushRegistry:(PKPushRegistry *)registry didUpdatePushCredentials:(PKPushCredentials *)credentials forType:(NSString *)type;

@property (nonatomic) UIBackgroundTaskIdentifier bgTask;

@end