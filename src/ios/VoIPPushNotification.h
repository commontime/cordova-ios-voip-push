#import <Cordova/CDVPlugin.h>
#import <PushKit/PushKit.h>
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

@interface VoIPPushNotification : CDVPlugin <PKPushRegistryDelegate> {
    BOOL foregroundAfterUnlock;
    AVAudioPlayer* audioPlayer;
    NSMutableArray *callbackIds;
    NSTimer *timer;
    BOOL appBroughtToFront;
    MPVolumeView *volumeView;
    UISlider *volumeSlider;
}

- (void) init:(CDVInvokedUrlCommand*) command;

@end
