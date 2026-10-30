#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <atomic>
#import <cmath>

// Private selectors are checked before use. Only SpringBoard is injected.
@interface AVSystemController : NSObject
+ (instancetype)sharedAVSystemController;
- (BOOL)getVolume:(float *)volume forCategory:(NSString *)category;
- (BOOL)setVolumeTo:(float)volume forCategory:(NSString *)category;
- (id)attributeForKey:(NSString *)key;
@end

@interface SBRingerControl : NSObject
- (void)setRingerMuted:(BOOL)muted;
- (BOOL)isRingerMuted;
- (BOOL)_accessibilityIsRingerMuted;
@end

@interface SBMainWorkspace : NSObject
+ (instancetype)sharedInstance;
- (SBRingerControl *)ringerControl;
@end

static CFStringRef const QPDomain = CFSTR("com.example.quietphone");
static CFStringRef const QPStateDomain = CFSTR("com.example.quietphone.state");
static std::atomic_bool QPEnabled(false);
static __weak SBRingerControl *QPLastRinger;
static NSMutableDictionary<NSString *, NSNumber *> *QPSavedVolumes;
static NSNumber *QPSavedRinger;
static dispatch_source_t QPWatchdog;
static BOOL QPApplying;
static BOOL QPScheduled;
static CFAbsoluteTime QPLastMediaWrite;

static id QPRead(CFStringRef domain, CFStringRef key) {
    return CFBridgingRelease(CFPreferencesCopyAppValue(key, domain));
}

static void QPPersistSnapshot(void) {
    CFPreferencesSetAppValue(CFSTR("Volumes"), (__bridge CFDictionaryRef)QPSavedVolumes, QPStateDomain);
    CFPreferencesSetAppValue(CFSTR("Ringer"), (__bridge CFTypeRef)QPSavedRinger, QPStateDomain);
    CFPreferencesAppSynchronize(QPStateDomain);
}

static AVSystemController *QPSystemAudio(void) {
    Class cls = NSClassFromString(@"AVSystemController");
    if (![cls respondsToSelector:@selector(sharedAVSystemController)]) return nil;
    AVSystemController *audio = [cls sharedAVSystemController];
    if (![audio respondsToSelector:@selector(getVolume:forCategory:)] ||
        ![audio respondsToSelector:@selector(setVolumeTo:forCategory:)]) return nil;
    return audio;
}

static NSString *QPRouteKey(AVSystemController *audio) {
    // Never restore a speaker's old volume to a different or unknown output.
    NSString *__unsafe_unretained *key = (NSString *__unsafe_unretained *)
        dlsym(RTLD_DEFAULT, "AVSystemController_ActiveAudioRouteAttribute");
    if (!key || !*key || ![audio respondsToSelector:@selector(attributeForKey:)]) return nil;
    id route = [audio attributeForKey:*key];
    return route ? [route description] : nil;
}

static SBRingerControl *QPRinger(void) {
    if (QPLastRinger) return QPLastRinger;
    Class cls = NSClassFromString(@"SBMainWorkspace");
    if (![cls respondsToSelector:@selector(sharedInstance)]) return nil;
    SBMainWorkspace *workspace = [cls sharedInstance];
    if (![workspace respondsToSelector:@selector(ringerControl)]) return nil;
    return [workspace ringerControl];
}

static NSNumber *QPRingerMuted(SBRingerControl *ringer) {
    if ([ringer respondsToSelector:@selector(isRingerMuted)]) return @([ringer isRingerMuted]);
    if ([ringer respondsToSelector:@selector(_accessibilityIsRingerMuted)])
        return @([ringer _accessibilityIsRingerMuted]);
    return nil;
}

// Main queue only. Save values before changing them, including across resprings.
static void QPEnforce(void) {
    if (!QPEnabled.load() || QPApplying) return;
    QPApplying = YES;
    @try {
        BOOL dirty = NO;
        SBRingerControl *ringer = QPRinger();
        NSNumber *muted = QPRingerMuted(ringer);
        if (!QPSavedRinger && muted) {
            QPSavedRinger = muted;
            dirty = YES;
        }
        AVSystemController *audio = QPSystemAudio();
        NSString *route = QPRouteKey(audio);
        float volume = 0;
        BOOL readable = [audio getVolume:&volume forCategory:@"Audio/Video"] && std::isfinite(volume);
        if (route && readable && !QPSavedVolumes[route]) {
            QPSavedVolumes[route] = @(fmaxf(0, fminf(1, volume)));
            dirty = YES;
        }
        if (dirty) QPPersistSnapshot();
        if ([ringer respondsToSelector:@selector(setRingerMuted:)] && (!muted || !muted.boolValue))
            [ringer setRingerMuted:YES];
        // A failed read must not create a write -> notification -> write loop.
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (audio && ((readable && volume > 0) || (!readable && now - QPLastMediaWrite >= 1.0))) {
            QPLastMediaWrite = now;
            [audio setVolumeTo:0 forCategory:@"Audio/Video"];
        }
    } @catch (NSException *exception) {
        NSLog(@"[QuietPhone] Audio interface failed: %@", exception.name);
    } @finally {
        QPApplying = NO;
    }
}

static void QPQueueEnforce(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (QPScheduled || !QPEnabled.load()) return;
        QPScheduled = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            QPScheduled = NO;
            QPEnforce();
        });
    });
}

static void QPRestore(void) {
    // Retry later if an audio service is temporarily unavailable.
    BOOL dirty = NO;
    @try {
        SBRingerControl *ringer = QPRinger();
        if (QPSavedRinger && [ringer respondsToSelector:@selector(setRingerMuted:)]) {
            [ringer setRingerMuted:QPSavedRinger.boolValue];
            QPSavedRinger = nil;
            dirty = YES;
        }
        AVSystemController *audio = QPSystemAudio();
        NSString *route = QPRouteKey(audio);
        NSNumber *volume = route ? QPSavedVolumes[route] : nil;
        if (audio && route) {
            if (!volume || [audio setVolumeTo:volume.floatValue forCategory:@"Audio/Video"]) {
                // Do not change inactive devices on future connects.
                [QPSavedVolumes removeAllObjects];
                dirty = YES;
            }
        }
    } @catch (NSException *exception) {
        NSLog(@"[QuietPhone] Restore failed: %@", exception.name);
    }
    if (dirty) QPPersistSnapshot();
}

static void QPReload(void) {
    CFPreferencesAppSynchronize(QPDomain);
    id enabledValue = QPRead(QPDomain, CFSTR("Enabled"));
    // A fresh install (or an upgrade without saved preferences) should mute
    // immediately. An explicit user choice to disable must still be respected.
    BOOL enabled = enabledValue ? [enabledValue boolValue] : YES;
    QPEnabled.store(enabled);
    if (enabled) QPEnforce();
    else QPRestore();
    // Notifications handle normal changes. Poll only while enabled or waiting
    // to restore, to recover missed audio-server events.
    if (enabled || QPSavedRinger || QPSavedVolumes.count) {
        if (!QPWatchdog) {
            QPWatchdog = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
            dispatch_source_set_timer(QPWatchdog, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                                      2 * NSEC_PER_SEC, NSEC_PER_SEC / 4);
            dispatch_source_set_event_handler(QPWatchdog, ^{
                if (QPEnabled.load()) QPEnforce();
                else {
                    QPRestore();
                    if (!QPSavedRinger && !QPSavedVolumes.count) {
                        dispatch_source_cancel(QPWatchdog);
                        QPWatchdog = nil;
                    }
                }
            });
            dispatch_resume(QPWatchdog);
        }
    } else if (QPWatchdog) {
        dispatch_source_cancel(QPWatchdog);
        QPWatchdog = nil;
    }
}

static void QPPreferencesChanged(CFNotificationCenterRef center, void *observer,
    CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{ QPReload(); });
}

%group RingerHooks
%hook SBRingerControl
- (void)setRingerMuted:(BOOL)muted {
    if ([NSThread isMainThread]) {
        QPLastRinger = self;
        if (QPEnabled.load() && !QPSavedRinger) {
            QPSavedRinger = QPRingerMuted(self);
            QPPersistSnapshot();
        }
    }
    %orig(QPEnabled.load() ? YES : muted);
}
%end
%end

%group MediaHooks
%hook AVSystemController
- (BOOL)setVolumeTo:(float)volume forCategory:(NSString *)category {
    // Other processes' requests are corrected by notifications and watchdog.
    return %orig((QPEnabled.load() && [category isEqualToString:@"Audio/Video"]) ? 0.0f : volume, category);
}
%end
%end

%ctor {
    @autoreleasepool {
        dlopen("/System/Library/PrivateFrameworks/Celestial.framework/Celestial", RTLD_LAZY | RTLD_GLOBAL);
        Class ringerClass = NSClassFromString(@"SBRingerControl");
        if ([ringerClass instancesRespondToSelector:@selector(setRingerMuted:)]) {
            %init(RingerHooks);
        }
        Class audioClass = NSClassFromString(@"AVSystemController");
        if ([audioClass instancesRespondToSelector:@selector(setVolumeTo:forCategory:)]) {
            %init(MediaHooks);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            CFPreferencesAppSynchronize(QPStateDomain);
            id saved = QPRead(QPStateDomain, CFSTR("Volumes"));
            QPSavedVolumes = [NSMutableDictionary dictionary];
            if ([saved isKindOfClass:NSDictionary.class]) {
                for (id key in saved) {
                    id value = saved[key];
                    if ([key isKindOfClass:NSString.class] && [value isKindOfClass:NSNumber.class] &&
                        std::isfinite([value floatValue]) && [value floatValue] >= 0 && [value floatValue] <= 1)
                        QPSavedVolumes[key] = value;
                }
            }
            id ringer = QPRead(QPStateDomain, CFSTR("Ringer"));
            QPSavedRinger = [ringer isKindOfClass:NSNumber.class] ? ringer : nil;
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                QPPreferencesChanged, CFSTR("com.example.quietphone/preferences-changed"), NULL,
                CFNotificationSuspensionBehaviorDeliverImmediately);
            NSMutableArray<NSString *> *events = [NSMutableArray arrayWithObject:UIApplicationDidBecomeActiveNotification];
            const char *symbols[] = {
                "AVSystemController_SystemVolumeDidChangeNotification",
                "AVSystemController_ActiveAudioRouteDidChangeNotification",
                "AVSystemController_ServerConnectionDiedNotification"
            };
            for (const char *symbol : symbols) {
                NSString *__unsafe_unretained *name = (NSString *__unsafe_unretained *)dlsym(RTLD_DEFAULT, symbol);
                if (name && *name) [events addObject:*name];
            }
            for (NSString *event in events) {
                [[NSNotificationCenter defaultCenter] addObserverForName:event object:nil
                    queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) { QPQueueEnforce(); }];
            }
            QPReload();
        });
    }
}
