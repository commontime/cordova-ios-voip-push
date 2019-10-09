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
    long lastPushTimestamp;
}

- (void) debounce:(SEL)action delay:(NSTimeInterval)delay withPayload:(PKPushPayload*)payload;
- (void) init:(CDVInvokedUrlCommand*)command;

@end
