#import <Cordova/CDVPlugin.h>
#import <PushKit/PushKit.h>
#import <AVFoundation/AVFoundation.h>

@interface VoIPPushNotification : CDVPlugin <PKPushRegistryDelegate> {
    BOOL foregroundAfterUnlock;
    BOOL appBroughtToFront;
    AVAudioPlayer* audioPlayer;
    AVAudioPlayer* voipAudioPlayer;
    AVAudioPlayer* exitAudioPlayer;
    AVAudioPlayer* ignoreListAudioPlayer;
    NSTimer* exitTimer;
    BOOL audioInitialised;
}

- (void) init:(CDVInvokedUrlCommand*)command;

@end
