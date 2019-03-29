#import "VoIPPushNotification.h"
#import <Cordova/CDV.h>
#import "LSApplicationWorkspace.h"
#import "DBManager.h"
#include "notify.h"

@import UserNotifications;

static NSString* SUPRESS_PROCESSING_KEY = @"supressProcessing";

@implementation VoIPPushNotification

- (void) onAppTerminate
{
    [[DBManager getSharedInstance] closeDB];
}

- (void) pluginInitialize
{
    [self addVolumeSlider];
}

- (void) addVolumeSlider
{
    // Below creates a hidden slider view as suvbiew. This is then used to enable
    // adjustment of the devices media volume without seeing any indication on the screen
    // that it has been changed.
    UIView *volumeHolder = [[UIView alloc] initWithFrame: CGRectMake(0, -25, 260, 20)];
    [volumeHolder setBackgroundColor: [UIColor clearColor]];
    [self.webView addSubview: volumeHolder];
    volumeView = [[MPVolumeView alloc] initWithFrame: volumeHolder.bounds];
    volumeView.alpha = 0.01;
    [volumeHolder addSubview: volumeView];
    for (UIView *subview in volumeView.subviews) {
        if([subview isKindOfClass:[UISlider class]]) {
            volumeSlider = subview;
        }
    }
}

- (void) removeVolumeSlider
{
    [volumeView removeFromSuperview];
}

- (void) setDeviceVolume: (double) volume
{
    if (volumeSlider == nil)
    {
        [self addVolumeSlider];
        volumeSlider.value = volume;
    }
    volumeSlider.value = volume;
}

#pragma mark JS Functions

- (void) init: (CDVInvokedUrlCommand*)command
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
    
    [self registerAppforDetectLockState];
    [self configureAudioPlayer];
    [self configureAudioSession];
    
    NSNotificationCenter* listener = [NSNotificationCenter defaultCenter];
    [listener addObserver:self selector:@selector(appBackgrounded) name:UIApplicationDidEnterBackgroundNotification object:nil];
    
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];[center requestAuthorizationWithOptions: (UNAuthorizationOptionAlert + UNAuthorizationOptionSound) completionHandler:^(BOOL granted, NSError * _Nullable error) {
    }];
}

- (void) stopVibration: (CDVInvokedUrlCommand*)command
{
    if (timer) [timer invalidate];
    
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) stopAudio: (CDVInvokedUrlCommand*)command
{
    if (!audioPlayer.isPlaying)
    {
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }
    else
    {
        stopAudioLooping = YES;
        stopAudioCallback = command.callbackId;
    }
}

- (void) didInitialiseApp: (CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:appBroughtToFront];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) supressProcessing: (CDVInvokedUrlCommand*)command
{
    if (![[command.arguments objectAtIndex:0] isEqual:[NSNull null]])
    {
        [self setSupressProcessing:[[command.arguments objectAtIndex:0] boolValue]];
    }
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) addToIgnoreList: (CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Failed to add message"];
    if (![[command.arguments objectAtIndex:0] isEqual:[NSNull null]])
    {
        BOOL success = [[DBManager getSharedInstance] addMessage:[[command.arguments objectAtIndex:0] longValue]];
        if (success) pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:success];
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) removeFromIgnoreList: (CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Failed to remove message"];
    if (![[command.arguments objectAtIndex:0] isEqual:[NSNull null]])
    {
        BOOL success = [[DBManager getSharedInstance] deleteMessage:[[command.arguments objectAtIndex:0] longValue]];
        if (success) pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK  messageAsBool:success];
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) checkIgnoreList: (CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Failed to check for message"];
    if (![[command.arguments objectAtIndex:0] isEqual:[NSNull null]])
    {
        BOOL exists = [[DBManager getSharedInstance] exists:[[command.arguments objectAtIndex:0] longValue]];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:exists];
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

#pragma mark Non JS Functions

- (void) setSupressProcessing: (BOOL) supress
{
    NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
    [preferences setBool:supress forKey:SUPRESS_PROCESSING_KEY];
    [preferences synchronize];
}

- (BOOL) getSupressProcessing
{
    NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
    return [preferences boolForKey:SUPRESS_PROCESSING_KEY];
}

- (void) pushRegistry: (PKPushRegistry *)registry didUpdatePushCredentials: (PKPushCredentials *)credentials forType: (NSString *)type
{
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

- (void) pushRegistry: (PKPushRegistry *)registry didReceiveIncomingPushWithPayload: (PKPushPayload *)payload forType: (NSString *)type
{
    if ([self getSupressProcessing]) return;
    
    NSDictionary *payloadDict = payload.dictionaryPayload[@"aps"];
    NSLog(@"[objC] didReceiveIncomingPushWithPayload: %@", payloadDict);
    
    NSMutableDictionary *newPushData = [[NSMutableDictionary alloc] init];
    
    BOOL foregrounded = NO;
    
    for (NSString *apsKey in payloadDict)
    {
        if ([apsKey compare:@"timestamp"] == NSOrderedSame)
        {
            if (![[payloadDict objectForKey:apsKey] isEqual:[NSNull null]])
            {
                if ([[DBManager getSharedInstance] exists:[[payloadDict objectForKey:apsKey] longValue]])
                {
                    return;
                }
            }
        }
    }
    
    for (NSString *apsKey in payloadDict)
    {
        if ([apsKey compare:@"bringToFront"] == NSOrderedSame)
        {
            if ([[payloadDict objectForKey:apsKey] boolValue])
            {
                foregrounded = [self foregroundApp];
                if (!foregrounded) {
                    
                    [self setDeviceVolume: 0.9];
                    [self configureAudioSession];
                    [audioPlayer play];
                    [self removeVolumeSlider];
                    
                    timer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
                        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
                    }];
                    
                    UILocalNotification *notification = [[UILocalNotification alloc] init];
                    notification.fireDate = [NSDate dateWithTimeIntervalSinceNow:0];
                    notification.alertBody = @"New Message Received";
                    notification.timeZone = [NSTimeZone defaultTimeZone];
                    [[UIApplication sharedApplication] scheduleLocalNotification:notification];
                }
            }
        }
        
        id apsObject = [payloadDict objectForKey:apsKey];
        
        if([apsKey compare:@"alert"] == NSOrderedSame)
            [newPushData setObject:apsObject forKey:@"message"];
        else
            [newPushData setObject:apsObject forKey:apsKey];
    }
    
    [newPushData setObject:@"APNS" forKey:@"service"];
    
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:newPushData];
    [pluginResult setKeepCallback:[NSNumber numberWithBool:YES]];
    for (id voipCallbackId in callbackIds) {
        [self.commandDelegate sendPluginResult:pluginResult callbackId:voipCallbackId];
    }
}

- (BOOL) foregroundApp
{
    foregroundAfterUnlock = NO;
    PrivateApi_LSApplicationWorkspace* workspace;
    workspace = [NSClassFromString(@"LSApplicationWorkspace") new];
    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
    BOOL isOpen = [workspace openApplicationWithBundleID:bundleId];
    if (!isOpen) {
        // Reason for failing to open up the app is almost certainly because the phone is locked.
        // Therefore set the flag to bring to the front after unlock to true.
        foregroundAfterUnlock = YES;
    } else {
        appBroughtToFront = YES;
    }
    return isOpen;
}

- (void) appBackgrounded
{
    appBroughtToFront = NO;
}

/**
 * Listen for device lock/unlock.
 */
- (void) registerAppforDetectLockState
{
    int notify_token;
    notify_register_dispatch("com.apple.springboard.lockstate", &notify_token,dispatch_get_main_queue(), ^(int token) {
        uint64_t state = UINT64_MAX;
        notify_get_state(token, &state);
        if(state == 0) {
            if (foregroundAfterUnlock) {
                [self foregroundApp];
            }
        }
    });
}

- (void) configureAudioSession
{
    AVAudioSession* session = [AVAudioSession sharedInstance];
    [session setActive:NO error:NULL];
    [session setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:NULL];
    [session setActive:YES error:NULL];
};

- (void) configureAudioPlayer
{
    NSString* path = [[NSBundle mainBundle] pathForResource:@"alert" ofType:@"m4a"];
    NSURL* url = [NSURL fileURLWithPath:path];
    audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:NULL];
    audioPlayer.delegate = self;
    audioPlayer.volume = 1.0;
};

- (void) audioPlayerDidFinishPlaying: (AVAudioPlayer *) player successfully: (BOOL) flag
{
    if (stopAudioLooping)
    {
        [audioPlayer stop];
        stopAudioLooping = NO;
        if (![stopAudioCallback isEqual:[NSNull null]])
        {
            CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:stopAudioCallback];
            stopAudioCallback = nil;
        }
    }
    else
    {
        [audioPlayer play];
    }
}

@end
