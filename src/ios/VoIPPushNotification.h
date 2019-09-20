#import <Cordova/CDV.h>
#import <PushKit/PushKit.h>
#import <AVFoundation/AVFoundation.h>

@interface VoIPPushNotification : CDVPlugin <PKPushRegistryDelegate> {
    AVAudioPlayer* exitAudioPlayer;
    NSTimer* exitTimer;
}

- (void)init:(CDVInvokedUrlCommand*)command;

@end