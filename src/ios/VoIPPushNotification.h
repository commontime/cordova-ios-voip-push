#import <Cordova/CDVPlugin.h>
#import <PushKit/PushKit.h>
#import <AVFoundation/AVFoundation.h>

@interface VoIPPushNotification : CDVPlugin <PKPushRegistryDelegate> {
    BOOL foregroundAfterUnlock;
    AVAudioPlayer* audioPlayer;
    NSMutableArray *callbackIds;
    NSTimer *timer;
    BOOL appBroughtToFront;
}

- (void) init:(CDVInvokedUrlCommand*) command;

@end