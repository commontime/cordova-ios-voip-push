#import "VoIPPushNotification.h"
#import <Cordova/CDV.h>
#import "LSApplicationWorkspace.h"
#include "notify.h"

NSString* const kAPPBackgroundJsNamespace = @"window.VoIPPushNotification";
NSString* const kAPPBackgroundEventDeactivate = @"deactivate";
NSString* const kAPPBackgroundEventActivate = @"activate";

@implementation VoIPPushNotification
{
    NSMutableArray *callbackIds;
}

- (void)init:(CDVInvokedUrlCommand*)command
{
    if (callbackIds == nil) {
        callbackIds = [[NSMutableArray alloc] init];
    }
    [callbackIds addObject:command.callbackId];
    
    NSLog(@"[objC] callbackId: %@", command.callbackId);

    //http://stackoverflow.com/questions/27245808/implement-pushkit-and-test-in-development-behavior/28562124#28562124
    PKPushRegistry *pushRegistry = [[PKPushRegistry alloc] initWithQueue:dispatch_get_main_queue()];
    pushRegistry.delegate = self;
    pushRegistry.desiredPushTypes = [NSSet setWithObject:PKPushTypeVoIP];
    
    foregroundAfterUnlock = NO;
    [self registerAppforDetectLockState];
    [self configureAudioPlayer];
    [self configureAudioSession];
    [self observeLifeCycle];
}

/**
 * Register the listener for pause and resume events.
 */
- (void) observeLifeCycle
{
    NSNotificationCenter* listener = [NSNotificationCenter defaultCenter];
    [listener addObserver:self selector:@selector(keepAwake) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [listener addObserver:self selector:@selector(stopKeepingAwake) name:UIApplicationWillEnterForegroundNotification object:nil];
    [listener addObserver:self selector:@selector(handleAudioSessionInterruption:) name:AVAudioSessionInterruptionNotification object:nil];
    [listener addObserver:self selector:@selector(handleCTAudioPlay:) name:@"CTIAudioPlay" object:nil];
}

- (void)pushRegistry:(PKPushRegistry *)registry didUpdatePushCredentials:(PKPushCredentials *)credentials forType:(NSString *)type{
    if([credentials.token length] == 0) {
        NSLog(@"[objC] No device token!");
        return;
    }

    //http://stackoverflow.com/a/9372848/534755
    NSLog(@"[objC] Device token: %@", credentials.token);
    const unsigned *tokenBytes = [credentials.token bytes];
    NSString *sToken = [NSString stringWithFormat:@"%08x%08x%08x%08x%08x%08x%08x%08x",
                         ntohl(tokenBytes[0]), ntohl(tokenBytes[1]), ntohl(tokenBytes[2]),
                         ntohl(tokenBytes[3]), ntohl(tokenBytes[4]), ntohl(tokenBytes[5]),
                         ntohl(tokenBytes[6]), ntohl(tokenBytes[7])];

    NSMutableDictionary* results = [NSMutableDictionary dictionaryWithCapacity:2];
    [results setObject:sToken forKey:@"deviceToken"];
    [results setObject:@"true" forKey:@"registration"];
    
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:results];
    [pluginResult setKeepCallback:[NSNumber numberWithBool:YES]]; //[pluginResult setKeepCallbackAsBool:YES];
    
    for (id voipCallbackId in callbackIds) {
        [self.commandDelegate sendPluginResult:pluginResult callbackId:voipCallbackId];
    }
}

- (void)pushRegistry:(PKPushRegistry *)registry didReceiveIncomingPushWithPayload:(PKPushPayload *)payload forType:(NSString *)type
{
    NSDictionary *payloadDict = payload.dictionaryPayload[@"aps"];
    NSLog(@"[objC] didReceiveIncomingPushWithPayload: %@", payloadDict);
    
    NSMutableDictionary *newPushData = [[NSMutableDictionary alloc] init];
    
    for(NSString *apsKey in payloadDict)
    {
        if ([apsKey compare:@"bringToFront"] == NSOrderedSame)
        {
            if ([[payloadDict objectForKey:apsKey] boolValue])
            {
                [self foregroundApp];
            }
        }
            
        id apsObject = [payloadDict objectForKey:apsKey];
        
        if([apsKey compare:@"alert"] == NSOrderedSame)
            [newPushData setObject:apsObject forKey:@"message"];
        else
            [newPushData setObject:apsObject forKey:apsKey];
    }
    
    [newPushData setObject:@"APNS" forKey:@"service"];
    
    // Play silent audio to keep the app alive
    [audioPlayer play];
    [self fireEvent:kAPPBackgroundEventActivate];
    
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:newPushData];
    [pluginResult setKeepCallback:[NSNumber numberWithBool:YES]];
    for (id voipCallbackId in callbackIds) {
        [self.commandDelegate sendPluginResult:pluginResult callbackId:voipCallbackId];
    }
}

- (void) foregroundApp
{
    PrivateApi_LSApplicationWorkspace* workspace;
    workspace = [NSClassFromString(@"LSApplicationWorkspace") new];
    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
    BOOL isOpen = [workspace openApplicationWithBundleID:bundleId];
    if (!isOpen) {
        // Reason for failing to open up the app is almost certainly because the phone is locked.
        // Therefore set the flag to bring to the front after unlock to true.
        foregroundAfterUnlock = YES;
    }
}

/**
 * Listen for device lock/unlock.
 */
- (void) registerAppforDetectLockState {
    int notify_token;
    notify_register_dispatch("com.apple.springboard.lockstate", &notify_token,dispatch_get_main_queue(), ^(int token) {
        uint64_t state = UINT64_MAX;
        notify_get_state(token, &state);
        if(state == 0) {
            if (foregroundAfterUnlock) {
                [self foregroundApp];
                foregroundAfterUnlock = NO;
            }
        }
    });
}

/**
 * Restart playing sound when interrupted by phone calls.
 */
- (void) handleAudioSessionInterruption:(NSNotification*)notification
{
    [self fireEvent:kAPPBackgroundEventDeactivate];
    [self keepAwake];
}

/**
 * Keep the app awake.
 */
- (void) keepAwake
{
    [self configureAudioSession];    
    [audioPlayer play];
    [self fireEvent:kAPPBackgroundEventActivate];
}

/**
 * Let the app going to sleep.
 */
- (void) stopKeepingAwake
{
    if (TARGET_IPHONE_SIMULATOR) {
        NSLog(@"BackgroundMode: On simulator apps never pause in background!");
    }
    if (audioPlayer.isPlaying) {
        [self fireEvent:kAPPBackgroundEventDeactivate];
    }
    [audioPlayer pause];
}

/**
 * Stop background audio correctly if the app itself is about to play audio.
 */
- (void) handleCTAudioPlay:(NSNotification*)notification
{
    [audioPlayer stop];
    [[AVAudioSession sharedInstance] setActive:NO error:nil];
}

- (void) configureAudioPlayer
{
    NSString* path = [[NSBundle mainBundle] pathForResource:@"appbeep" ofType:@"m4a"];
    NSURL* url = [NSURL fileURLWithPath:path];
    audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:NULL];
    audioPlayer.volume = 40;
};

- (void) configureAudioSession
{
    AVAudioSession* session = [AVAudioSession sharedInstance];
    [session setActive:NO error:NULL];
    [session setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:NULL];
    [session setActive:YES error:NULL];
};

/**
 * Method to fire an event with some parameters in the browser.
 */
- (void) fireEvent:(NSString*)event
{
    NSString* active =
    [event isEqualToString:kAPPBackgroundEventActivate] ? @"true" : @"false";
    NSString* flag = [NSString stringWithFormat:@"%@._isActive=%@;", kAPPBackgroundJsNamespace, active];
    NSString* depFn = [NSString stringWithFormat:@"%@.on%@();", kAPPBackgroundJsNamespace, event];
    NSString* fn = [NSString stringWithFormat:@"%@.fireEvent('%@');",  kAPPBackgroundJsNamespace, event];
    NSString* js = [NSString stringWithFormat:@"%@%@%@", flag, depFn, fn];
    [self.commandDelegate evalJs:js];
};

@end