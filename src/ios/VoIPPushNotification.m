#import "VoIPPushNotification.h"
#import <Cordova/CDV.h>
#import "APPMethodMagic.h"
#import "LSApplicationWorkspace.h"
#import <AudioToolbox/AudioToolbox.h>
#include "notify.h"

@import UserNotifications;

@implementation VoIPPushNotification
{
    NSMutableArray *callbackIds;
    NSTimer *timer;
    BOOL appBroughtToFront;
}

+ (void)load
{
    [self swizzleWKWebViewEngine];
}

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
    
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];[center requestAuthorizationWithOptions: (UNAuthorizationOptionAlert + UNAuthorizationOptionSound) completionHandler:^(BOOL granted, NSError * _Nullable error) {
        // Enable or disable features based on authorization.
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
    if (audioPlayer) [audioPlayer stop];
        
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) didInitialiseApp: (CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:appBroughtToFront];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
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
    NSDictionary *payloadDict = payload.dictionaryPayload[@"aps"];
    NSLog(@"[objC] didReceiveIncomingPushWithPayload: %@", payloadDict);
    
    NSMutableDictionary *newPushData = [[NSMutableDictionary alloc] init];    
    
    BOOL foregrounded = NO;

    for(NSString *apsKey in payloadDict)
    {
        if ([apsKey compare:@"bringToFront"] == NSOrderedSame)
        {
            if ([[payloadDict objectForKey:apsKey] boolValue])
            {
                foregrounded = [self foregroundApp];                
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

    if (!foregrounded) {
        
        UILocalNotification *notification = [[UILocalNotification alloc] init];
        notification.fireDate = [NSDate dateWithTimeIntervalSinceNow:0];
        notification.alertBody = @"New Message Received";
        notification.timeZone = [NSTimeZone defaultTimeZone];
        [[UIApplication sharedApplication] scheduleLocalNotification:notification];
        
        [self configureAudioSession];
        [audioPlayer play];
        
        timer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
             AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
        }];
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
    audioPlayer.volume = 50;
    audioPlayer.numberOfLoops = -1;
};

#pragma mark -
#pragma mark Swizzling

+ (BOOL) isRunningWebKit
{
    return IsAtLeastiOSVersion(@"8.0") && NSClassFromString(@"CDVWKWebViewEngine");
}

/**
 * Method to swizzle.
 */
+ (NSString*) wkProperty
{
    NSString* str = @"X2Fsd2F5c1J1bnNBdEZvcmVncm91bmRQcmlvcml0eQ==";
    NSData* data  = [[NSData alloc] initWithBase64EncodedString:str options:0];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

/**
 * Swizzle some implementations of CDVWKWebViewEngine.
 */
+ (void) swizzleWKWebViewEngine
{
    if (![self isRunningWebKit])
        return;
    
    Class wkWebViewEngineCls = NSClassFromString(@"CDVWKWebViewEngine");
    SEL selector = NSSelectorFromString(@"createConfigurationFromSettings:");
    
    SwizzleSelectorWithBlock_Begin(wkWebViewEngineCls, selector)
    ^(CDVPlugin *self, NSDictionary *settings) {
        id obj = ((id (*)(id, SEL, NSDictionary*))_imp)(self, _cmd, settings);
        
        [obj setValue:[NSNumber numberWithBool:YES]
               forKey:[VoIPPushNotification wkProperty]];
        
        [obj setValue:[NSNumber numberWithBool:NO]
               forKey:@"requiresUserActionForMediaPlayback"];
        
        return obj;
    }
    SwizzleSelectorWithBlock_End;
}

@end