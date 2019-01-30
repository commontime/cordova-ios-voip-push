#import <Cordova/CDVPlugin.h>
#import <PushKit/PushKit.h>

@interface VoIPPushNotification : CDVPlugin <PKPushRegistryDelegate> {
    BOOL foregroundAfterUnlock;
}

- (void) init:(CDVInvokedUrlCommand*)command;

@end
