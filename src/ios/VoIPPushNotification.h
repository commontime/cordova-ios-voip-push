#import <Cordova/CDVPlugin.h>
#import <PushKit/PushKit.h>
#import <AVFoundation/AVFoundation.h>

@interface VoIPPushNotification : CDVPlugin <PKPushRegistryDelegate> {
    BOOL foregroundAfterUnlock;
    BOOL appBroughtToFront;
    BOOL shouldExitApp;
    AVAudioPlayer* audioPlayer;
    AVAudioPlayer* voipAudioPlayer;
    AVAudioPlayer* exitAudioPlayer;
    AVAudioPlayer* ignoreListAudioPlayer;
}

- (void) init:(CDVInvokedUrlCommand*)command;

@end
