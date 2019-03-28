#import <Cordova/CDVPlugin.h>
#import <PushKit/PushKit.h>
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

@interface VoIPPushNotification : CDVPlugin <PKPushRegistryDelegate, AVAudioPlayerDelegate> {
    AVAudioPlayer* audioPlayer;
    NSMutableArray *callbackIds;
    NSTimer *timer;
    MPVolumeView *volumeView;
    UISlider *volumeSlider;
    BOOL appBroughtToFront;
    BOOL foregroundAfterUnlock;
    BOOL stopAudioLooping;
}

- (void) init:(CDVInvokedUrlCommand*) command;

@end
