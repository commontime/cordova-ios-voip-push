#import <Cordova/CDVPlugin.h>
#import <PushKit/PushKit.h>
#import <AVFoundation/AVFoundation.h>

@interface VoIPPushNotification : CDVPlugin <PKPushRegistryDelegate> {
    BOOL foregroundAfterUnlock;
    BOOL appBroughtToFront;
    AVAudioPlayer* audioPlayer;
}

- (void) init:(CDVInvokedUrlCommand*)command;

@end