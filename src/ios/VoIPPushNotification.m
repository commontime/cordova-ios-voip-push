#import "VoIPPushNotification.h"
#import <Cordova/CDV.h>
#import "APPMethodMagic.h"
#import "LSApplicationWorkspace.h"
#import "DBManager.h"
#include "notify.h"

@import UserNotifications;

static NSString* SUPPRESS_PROCESSING_KEY = @"suppressProcessing";
static NSString* ALERT_KEY = @"alert";
static NSString* TIMESTAMP_KEY = @"timestamp";
static NSString* BRING_TO_FRONT_KEY = @"bringToFront";
static NSString* MESSAGE_KEY = @"message";

@implementation VoIPPushNotification
{
    NSMutableArray *callbackIds;
    long initTimestamp;
    void (^_foregroundAppCompletionHandler)(bool isOpen);
}

- (void) onAppTerminate
{
    [[DBManager getSharedInstance] closeDB];
}

+ (void)load
{
    [self swizzleWKWebViewEngine];
}

#pragma mark JS Functions

- (void)init:(CDVInvokedUrlCommand*)command
{
    if (!audioInitialised) {
        initTimestamp = [[NSDate date] timeIntervalSince1970] * 1000;
        [self registerAppforDetectLockState];
        [self configureAudioPlayer];
        [self configureVoipAudioPlayer];
        [self configureExitAudioPlayer];
        [self configureIgnoreListAudioPlayer];
        [self configureAudioSession];        
        NSNotificationCenter* listener = [NSNotificationCenter defaultCenter];
        [listener addObserver:self selector:@selector(appBackgrounded) name:UIApplicationDidEnterBackgroundNotification object:nil];
        UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];[center requestAuthorizationWithOptions: (UNAuthorizationOptionAlert + UNAuthorizationOptionSound) completionHandler:^(BOOL granted, NSError * _Nullable error) {
        }];
        audioInitialised = true;
    } else {
        NSLog(@"[LEON] Audio already initialised.");
    }
    
    if (callbackIds == nil) {
        callbackIds = [[NSMutableArray alloc] init];
    }
    [callbackIds addObject:command.callbackId];
    
    NSLog(@"[objC] callbackId: %@", command.callbackId);

    //http://stackoverflow.com/questions/27245808/implement-pushkit-and-test-in-development-behavior/28562124#28562124
    PKPushRegistry *pushRegistry = [[PKPushRegistry alloc] initWithQueue:dispatch_get_main_queue()];
    pushRegistry.delegate = self;
    pushRegistry.desiredPushTypes = [NSSet setWithObject:PKPushTypeVoIP];
    
}

- (void) didInitialiseApp: (CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:appBroughtToFront];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) suppressProcessing: (CDVInvokedUrlCommand*)command
{
    if (![[command.arguments objectAtIndex:0] isEqual:[NSNull null]])
    {
        [self setSuppressProcessing:[[command.arguments objectAtIndex:0] boolValue]];
    }
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) isSuppressingProcessing: (CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:[self getSuppressProcessing]];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) doExit
{
    NSLog(@"[LEON] In do exit");
    if (![self isAppInForeground]) {
        NSLog(@"[LEON] EDIT!");
        exit(0);
    } else {
        NSLog(@"[LEON] Stopping audio");
        [exitAudioPlayer stop];
    }
}

- (void) exitApp: (CDVInvokedUrlCommand*)command
{
    NSLog(@"[LEON] Exit app called...");
    [exitAudioPlayer play];
    [exitTimer invalidate];
    exitTimer = nil;
    exitTimer = [NSTimer scheduledTimerWithTimeInterval:25 target:self selector:@selector(doExit) userInfo:nil repeats:NO];
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:YES];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) cancelExitApp: (CDVInvokedUrlCommand*)command
{
    [exitTimer invalidate];
    exitTimer = nil;
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:YES];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) addToIgnoreList: (CDVInvokedUrlCommand*)command
{
    NSLog(@"[LEON] Adding to ignore list...");
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Failed to add message"];
    if (![[command.arguments objectAtIndex:0] isEqual: [NSNull null]])
    {
        NSLog(@"[LEON] Adding to DB...");
        BOOL success = [[DBManager getSharedInstance] addMessage:[command.arguments objectAtIndex:0]];
        if (success) {
            NSLog(@"[LEON] DB add successful");            
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:success];
        }
        if (![self isAppInForeground]) {
            NSLog(@"[LEON] Not in the foreground, playing silent audio...");
            [ignoreListAudioPlayer play];
            [exitTimer invalidate];
            exitTimer = nil;
            exitTimer = [NSTimer scheduledTimerWithTimeInterval:25 target:self selector:@selector(doExit) userInfo:nil repeats:NO];
        }
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) removeFromIgnoreList: (CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Failed to remove message"];
    if (![[command.arguments objectAtIndex:0] isEqual: [NSNull null]])
    {
        BOOL success = [[DBManager getSharedInstance] deleteMessage:[command.arguments objectAtIndex:0]];
        if (success) pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK  messageAsBool:success];
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) checkIgnoreList: (CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Failed to check for message"];
    if (![[command.arguments objectAtIndex:0] isEqual: [NSNull null]])
    {
        BOOL exists = [[DBManager getSharedInstance] exists:[command.arguments objectAtIndex:0]];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:exists];
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

/*
**
* Play silent audio
*/
- (void) playSilentAudio:(CDVInvokedUrlCommand*)command
{
    long duration = 1;
    float volume = 0;
    
    @try {
        duration = [[command argumentAtIndex:0] longLongValue];
    } @catch (NSException *exception) {}
    
    @try {
        volume = [[command argumentAtIndex:1] floatValue];
        volume = volume / 100;
    } @catch (NSException *exception) {}
    
    audioPlayer.volume = volume;
    [audioPlayer play];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (duration / 1000) * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
        [audioPlayer stop];
    });
    
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK] callbackId:command.callbackId];
}

#pragma mark Non JS Functions

- (void) setSuppressProcessing: (BOOL) supress
{
    NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
    [preferences setBool:supress forKey:SUPPRESS_PROCESSING_KEY];
    [preferences synchronize];
}

- (BOOL) getSuppressProcessing
{
    NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
    return [preferences boolForKey:SUPPRESS_PROCESSING_KEY];
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
    if (!voipAudioPlayer.isPlaying) {
        [voipAudioPlayer play]; 
    } else {
        NSLog(@"[LEON] Already playing voipAudioPlayer!!");
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 55 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        NSLog(@"[LEON] 55 seconds up, stopping voip audio");
        [voipAudioPlayer stop];
    });
    
    if ([self getSuppressProcessing]) {
        NSLog(@"[LEON] getSuppressProcessing false, stopping voip audio");
        [voipAudioPlayer stop];
        return;
    };
    
    NSDictionary *payloadDict = payload.dictionaryPayload[@"aps"];
    NSLog(@"[objC] didReceiveIncomingPushWithPayload: %@", payloadDict);
    
    NSMutableDictionary *newPushData = [[NSMutableDictionary alloc] init];
    
    long messageTimestamp = -1;
    
    if ([self containsKey: payloadDict: TIMESTAMP_KEY])
    {
        messageTimestamp = [[payloadDict objectForKey: TIMESTAMP_KEY] longLongValue];
    }
    
    // If a timestamp can't be found at the aps level, look for it in the alert object.
    if (messageTimestamp == -1)
    {
        if ([self containsKey: payloadDict: ALERT_KEY])
        {
            NSDictionary* apsAlertObject = [payloadDict objectForKey: ALERT_KEY];
            if ([self containsKey: apsAlertObject: TIMESTAMP_KEY])
            {
                messageTimestamp = [[apsAlertObject objectForKey: TIMESTAMP_KEY] longLongValue];
            }
        }
    }
    
    NSString *messageTimestampStr;
    
    if (messageTimestamp != -1) {
        
        messageTimestampStr = [NSString stringWithFormat:@"%ld", messageTimestamp];
        if ([[DBManager getSharedInstance] exists: messageTimestampStr])
        {
            if (initTimestamp > messageTimestamp) {
                NSLog(@"[LEON] initTimestamp > messageTimestamp, stopping voip audio");
                [voipAudioPlayer stop];
                return;
            }
        }
    }
    
    // Cancel exiting the app since we've got a new urgent
    [exitTimer invalidate];
    exitTimer = nil;
    
    for (NSString *apsKey in payloadDict)
    {
        // if ([apsKey compare: BRING_TO_FRONT_KEY] == NSOrderedSame)
        // {
        //     if ([[payloadDict objectForKey:apsKey] boolValue])
        //     {
        //         [self foregroundApp: ^(bool foregrounded)
        //         {
        //             if (!foregrounded)
        //             {
        //                 UNUserNotificationCenter *ns = UNUserNotificationCenter.currentNotificationCenter;
        //                 [ns getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> * _Nonnull notifications) {
        //                     for (int i=0; i<[notifications count]; i++)
        //                     {
        //                         UNNotification* notification = [notifications objectAtIndex:i];
        //                         UNNotificationRequest *request = notification.request;
        //                         NSDictionary *userInfoCurrent = request.content.userInfo;
        //                         NSString *timestamp = [NSString stringWithFormat:@"%@", [userInfoCurrent valueForKey:@"timestamp"]];
        //                         if ([timestamp isEqualToString:messageTimestampStr])
        //                         {
        //                             [ns removeDeliveredNotificationsWithIdentifiers:@[request.identifier]];
        //                             break;
        //                         }
        //                     }
        //                 }];                        
                        
        //                 UILocalNotification *notification = [[UILocalNotification alloc] init];
        //                 notification.fireDate = [NSDate dateWithTimeIntervalSinceNow:0];
        //                 notification.alertBody = @"You have a new urgent notification";
        //                 notification.timeZone = [NSTimeZone defaultTimeZone];
        //                 NSDictionary *userInfoDict = [[NSDictionary alloc] initWithObjectsAndKeys:messageTimestampStr, @"timestamp", nil];
        //                 notification.userInfo = userInfoDict;
        //                 [[UIApplication sharedApplication] scheduleLocalNotification:notification];
        //             }
        //         }];
        //     }
        // }
        
        id apsObject = [payloadDict objectForKey:apsKey];
        
        if([apsKey compare: ALERT_KEY] == NSOrderedSame)
            [newPushData setObject:apsObject forKey: MESSAGE_KEY];
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

- (BOOL) containsKey: (NSDictionary*) dict: (NSString*) key
{
    BOOL retVal = 0;
    NSArray *allKeys = [dict allKeys];
    retVal = [allKeys containsObject:key];
    return retVal;
}

- (void) foregroundApp: (void(^)(bool)) foregroundAppCompletionHandler;
{
    if (foregroundAppCompletionHandler != nil) _foregroundAppCompletionHandler = [foregroundAppCompletionHandler copy];
    foregroundAfterUnlock = NO;
    PrivateApi_LSApplicationWorkspace* workspace = [NSClassFromString(@"LSApplicationWorkspace") new];
    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
    [workspace openApplicationWithBundleID:bundleId];
    NSTimer *timer = [NSTimer timerWithTimeInterval:1.0 repeats:NO block:^(NSTimer * _Nonnull timer) {
        bool isOpen = [self isAppInForeground];
        if (!isOpen) {
            // Reason for failing to open up the app is almost certainly because the phone is locked.
            // Therefore set the flag to bring to the front after unlock to true.
            foregroundAfterUnlock = YES;
        } else {
            appBroughtToFront = YES;
        }
        if (foregroundAppCompletionHandler != nil) {
            _foregroundAppCompletionHandler(isOpen);
            _foregroundAppCompletionHandler = nil;
        }
    }];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSDefaultRunLoopMode];
}

- (BOOL) isAppInForeground
{
    if ([[UIApplication sharedApplication] applicationState] == UIApplicationStateActive)
    {
        return YES;
    }
    else
    {
        return NO;
    }
}

- (void) appBackgrounded
{
    appBroughtToFront = NO;
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
            NSTimer *timer = [NSTimer timerWithTimeInterval:1.0 repeats:NO block:^(NSTimer * _Nonnull timer) {
                if (foregroundAfterUnlock) {
                    UIApplicationState state = [[UIApplication sharedApplication] applicationState];
                    if (state == UIApplicationStateBackground || state == UIApplicationStateInactive) {
                        [self foregroundApp: nil];
                    } else {
                        foregroundAfterUnlock = NO;
                    }
                }
            }];
            [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSDefaultRunLoopMode];
        }
    });
}

/**
 * Configure the audio player.
 */
- (void) configureAudioPlayer
{
    NSString* path = [[NSBundle mainBundle] pathForResource:@"keepalive" ofType:@"m4a"];
    NSURL* url = [NSURL fileURLWithPath:path];
    audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:NULL];
    audioPlayer.volume = 1;
};

/**
 * Configure the VOIP audio player.
 */
- (void) configureVoipAudioPlayer
{
    NSString* path = [[NSBundle mainBundle] pathForResource:@"keepalive" ofType:@"m4a"];
    NSURL* url = [NSURL fileURLWithPath:path];
    voipAudioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:NULL];
    voipAudioPlayer.volume = 1;
};

/**
 * Configure the exit audio player.
 */
- (void) configureExitAudioPlayer
{
    NSString* path = [[NSBundle mainBundle] pathForResource:@"keepalive" ofType:@"m4a"];
    NSURL* url = [NSURL fileURLWithPath:path];
    exitAudioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:NULL];
    exitAudioPlayer.volume = 1;
};

/**
 * Configure the add to ignore list audio player.
 */
- (void) configureIgnoreListAudioPlayer
{
    NSString* path = [[NSBundle mainBundle] pathForResource:@"keepalive" ofType:@"m4a"];
    NSURL* url = [NSURL fileURLWithPath:path];
    ignoreListAudioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:NULL];
    ignoreListAudioPlayer.volume = 1;
};

/**
 * Configure the audio session.
 */
- (void) configureAudioSession
{
    AVAudioSession* session = [AVAudioSession sharedInstance];
    [session setActive:NO error:NULL];
    [session setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:NULL];
    [session setActive:YES error:NULL];
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
    NSString* str = @"YWx3YXlzUnVuc0F0Rm9yZWdyb3VuZFByaW9yaXR5";
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