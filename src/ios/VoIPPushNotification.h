#import <Cordova/CDV.h>
#import <PushKit/PushKit.h>

@interface VoIPPushNotification : CDVPlugin <PKPushRegistryDelegate>

- (void)init:(CDVInvokedUrlCommand*)command;

@end