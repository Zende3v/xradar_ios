#import "EONASystemMedia.h"
#import <dispatch/dispatch.h>

@interface EONASystemMediaSnapshot ()
@property (nonatomic, readwrite, copy) NSString *title;
@property (nonatomic, readwrite, copy) NSString *artist;
@property (nonatomic, readwrite, copy) NSData *artwork;
@property (nonatomic, readwrite, strong) NSNumber *playing;
@property (nonatomic, readwrite) BOOL playingReliable;
@property (nonatomic, readwrite, strong) NSNumber *processIdentifier;
@property (nonatomic, readwrite, copy) NSDictionary<NSNumber *, NSNumber *> *commands;
@property (nonatomic, readwrite, strong) NSNumber *forwardInterval;
@property (nonatomic, readwrite, strong) NSNumber *backwardInterval;
@end

@implementation EONASystemMediaSnapshot
@end

#if EONA_EXPERIMENTAL_SYSTEM_MEDIA
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <math.h>
#import <limits.h>

// ABI : headers Theos, WebKit Apple et dump iOS. Aucun symbole lié directement.
typedef Boolean (*EONASendCommand)(int command, NSDictionary *userInfo);
typedef Boolean (*EONASendToApp)(uint32_t command, CFDictionaryRef options, void *origin,
                               CFStringRef applicationID, uint32_t applicationOptions,
                               dispatch_queue_t queue, void (^completion)(uint32_t error, CFArrayRef statuses));
typedef void (*EONAReadInfo)(dispatch_queue_t queue, void (^completion)(CFDictionaryRef information));
typedef void (*EONAReadPlaying)(dispatch_queue_t queue, void (^completion)(Boolean playing));
typedef void (*EONAReadPID)(dispatch_queue_t queue, void (^completion)(int processIdentifier));
typedef void *(*EONALocalOrigin)(void);
typedef void (*EONAReadCommands)(void *origin, dispatch_queue_t queue, void (^completion)(CFArrayRef commands));
typedef void (*EONARegisterNotifications)(dispatch_queue_t queue);
typedef void (*EONAUnregisterNotifications)(void);

@protocol EONACommandInfo <NSObject>
- (uint32_t)command;
- (BOOL)isEnabled;
- (NSDictionary *)options;
@end

@protocol EONANowPlayingRequest <NSObject>
+ (id)localNowPlayingItem;
+ (id)localNowPlayingPlayerPath;
+ (uint32_t)localPlaybackState;
+ (NSArray *)localSupportedCommands;
@end

@protocol EONAContentItem <NSObject>
- (NSDictionary *)nowPlayingInfo;
@end

static void *mediaHandle;
static EONASendCommand sendCommand;
static EONASendToApp sendToApp;
static EONAReadInfo readInfo;
static EONAReadPlaying readPlaying;
static EONAReadPID readPID;
static EONALocalOrigin localOrigin;
static EONAReadCommands readCommands;
static EONARegisterNotifications registerNotifications;
static EONAUnregisterNotifications unregisterNotifications;
static NSArray<id> *notificationObservers;
// Accès main uniquement. Repli synchrone borné à une opération, même après timeout UI.
static BOOL requestBusy;

static void loadMediaRemote(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Conservé chargé : callbacks peuvent arriver après timeout.
        mediaHandle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LOCAL | RTLD_LAZY);
        if (!mediaHandle) return;
        sendCommand = (EONASendCommand)dlsym(mediaHandle, "MRMediaRemoteSendCommand");
        sendToApp = (EONASendToApp)dlsym(mediaHandle, "MRMediaRemoteSendCommandToApp");
        readInfo = (EONAReadInfo)dlsym(mediaHandle, "MRMediaRemoteGetNowPlayingInfo");
        readPlaying = (EONAReadPlaying)dlsym(mediaHandle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
        readPID = (EONAReadPID)dlsym(mediaHandle, "MRMediaRemoteGetNowPlayingApplicationPID");
        localOrigin = (EONALocalOrigin)dlsym(mediaHandle, "MRMediaRemoteGetLocalOrigin");
        readCommands = (EONAReadCommands)dlsym(mediaHandle, "MRMediaRemoteGetSupportedCommandsForOrigin");
        registerNotifications = (EONARegisterNotifications)dlsym(mediaHandle, "MRMediaRemoteRegisterForNowPlayingNotifications");
        unregisterNotifications = (EONAUnregisterNotifications)dlsym(mediaHandle, "MRMediaRemoteUnregisterForNowPlayingNotifications");
    });
}

static NSString *mediaKey(const char *name) {
    CFStringRef *key = mediaHandle ? (CFStringRef *)dlsym(mediaHandle, name) : NULL;
    return key && *key ? (__bridge NSString *)*key : nil;
}

static id infoValue(NSDictionary *info, const char *name) {
    NSString *key = mediaKey(name);
    // Certains systèmes conservent clé littérale sans exporter symbole.
    return (key ? info[key] : nil) ?: info[@(name)];
}

static NSString *textValue(NSDictionary *info, const char *name) {
    id value = infoValue(info, name);
    return [value isKindOfClass:NSString.class] && [value length] > 0 ? [value copy] : nil;
}

static NSNumber *playingFromInfo(NSDictionary *info) {
    id rate = infoValue(info, "kMRMediaRemoteNowPlayingInfoPlaybackRate");
    if (![rate isKindOfClass:NSNumber.class] || !isfinite([rate doubleValue]) || [rate doubleValue] < 0) return nil;
    return @([rate doubleValue] > 0);
}

static NSNumber *notificationPlaying(NSDictionary *info) {
    id value = infoValue(info, "kMRMediaRemoteNowPlayingApplicationIsPlayingUserInfoKey");
    if (![value isKindOfClass:NSNumber.class]) return playingFromInfo(info);
    double state = [value doubleValue];
    return state == 0 || state == 1 ? @(state == 1) : nil;
}

static NSNumber *notificationPID(NSDictionary *info) {
    id value = infoValue(info, "kMRMediaRemoteNowPlayingApplicationPIDUserInfoKey");
    if (![value isKindOfClass:NSNumber.class]) return nil;
    double processIdentifier = [value doubleValue];
    return isfinite(processIdentifier) && processIdentifier > 0 && processIdentifier <= INT_MAX
        && floor(processIdentifier) == processIdentifier ? @([value intValue]) : nil;
}

static NSData *artworkValue(NSDictionary *info) {
    id artwork = infoValue(info, "kMRMediaRemoteNowPlayingInfoArtworkData");
    return [artwork isKindOfClass:NSData.class] && [artwork length] <= 8 * 1024 * 1024 ? artwork : nil;
}

static NSNumber *preferredInterval(NSDictionary *options) {
    id intervals = infoValue(options, "kMRMediaRemoteOptionSkipInterval")
        ?: infoValue(options, "kMRMediaRemoteCommandInfoPreferredIntervalsKey");
    NSArray *values = [intervals isKindOfClass:NSArray.class] ? intervals : (intervals ? @[intervals] : @[]);
    for (id value in values) {
        if ([value isKindOfClass:NSNumber.class] && isfinite([value doubleValue]) && [value doubleValue] > 0) return value;
    }
    return nil;
}

static void applyCommands(EONASystemMediaSnapshot *snapshot, NSArray *commands) {
    if (![commands isKindOfClass:NSArray.class]) return;
    NSMutableDictionary *supported = [NSMutableDictionary dictionary];
    for (id<EONACommandInfo> command in commands) {
        if (![command respondsToSelector:@selector(command)] || ![command respondsToSelector:@selector(isEnabled)]) continue;
        uint32_t code = [command command];
        BOOL enabled = [command isEnabled];
        supported[@(code)] = @(enabled);
        if (!enabled || ![command respondsToSelector:@selector(options)]) continue;
        id options = [command options];
        if (![options isKindOfClass:NSDictionary.class]) continue;
        if (code == EONASystemMediaCommandSkipForward) snapshot.forwardInterval = preferredInterval(options);
        if (code == EONASystemMediaCommandSkipBackward) snapshot.backwardInterval = preferredInterval(options);
    }
    // Liste vide peut venir filtrage iOS : conserver inconnu, pas tout désactiver.
    if (supported.count) snapshot.commands = supported;
}
#endif

@implementation EONASystemMedia

+ (BOOL)isEnabled {
#if EONA_EXPERIMENTAL_SYSTEM_MEDIA
    return YES;
#else
    return NO;
#endif
}

+ (BOOL)prepare {
#if EONA_EXPERIMENTAL_SYSTEM_MEDIA
    loadMediaRemote();
    return sendCommand != NULL || sendToApp != NULL;
#else
    return NO;
#endif
}

+ (BOOL)send:(EONASystemMediaCommand)command interval:(NSNumber *)interval
  completion:(void (^)(NSNumber *, NSArray<NSNumber *> *))completion {
#if EONA_EXPERIMENTAL_SYSTEM_MEDIA
    if (![self prepare]) return NO;
    BOOL skip = command == EONASystemMediaCommandSkipForward || command == EONASystemMediaCommandSkipBackward;
    BOOL playback = command == EONASystemMediaCommandPlay || command == EONASystemMediaCommandPause || command == EONASystemMediaCommandToggle;
    if (!skip && !playback && command != EONASystemMediaCommandNext && command != EONASystemMediaCommandPrevious) return NO;
    NSString *intervalKey = mediaKey("kMRMediaRemoteOptionSkipInterval");
    if (skip && (!intervalKey || !interval || !isfinite(interval.doubleValue) || interval.doubleValue <= 0)) return NO;
    NSDictionary *options = skip ? @{intervalKey: interval} : nil;

    // Navigation conservée. Lecture explicite utilise même transport legacy, un envoi par clic.
    if (sendCommand && (playback || !sendToApp)) {
        BOOL accepted = sendCommand((int)command, options) != 0;
        if (accepted) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, nil); });
        return accepted;
    }
    if (!sendToApp) return NO;
    __block BOOL finished = NO;
    void (^finish)(NSNumber *, NSArray *) = ^(NSNumber *error, NSArray *statuses) {
        if (finished) return;
        finished = YES;
        completion(error, statuses);
    };
    BOOL accepted = sendToApp((uint32_t)command, (__bridge CFDictionaryRef)options, NULL, NULL, 0,
        dispatch_get_main_queue(), ^(uint32_t error, CFArrayRef raw) {
            NSArray *copy = raw ? [(__bridge NSArray *)raw copy] : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                NSMutableArray *statuses = [NSMutableArray array];
                if ([copy isKindOfClass:NSArray.class]) {
                    for (id value in copy) if ([value isKindOfClass:NSNumber.class]) [statuses addObject:value];
                }
                finish(@(error), statuses.count ? statuses : nil);
            });
        }) != 0;
    if (!accepted) return NO;
    // Aucun accusé ne démontre changement piste. Timeout garde résultat inconnu.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ finish(nil, nil); });
    return YES;
#else
    return NO;
#endif
}

+ (void)read:(void (^)(EONASystemMediaSnapshot *))completion {
#if EONA_EXPERIMENTAL_SYSTEM_MEDIA
    loadMediaRemote();
    dispatch_async(dispatch_get_main_queue(), ^{
        EONASystemMediaSnapshot *snapshot = [EONASystemMediaSnapshot new];
        __block BOOL infoDone = readInfo == NULL;
        __block BOOL playingDone = readPlaying == NULL;
        __block BOOL pidDone = readPID == NULL;
        __block BOOL commandsDone = readCommands == NULL || localOrigin == NULL;
        __block BOOL requestDone = requestBusy;
        __block BOOL finished = NO;
        __block NSDictionary *information;
        __block NSNumber *legacyPlaying;
        __block NSDictionary *requestInformation;
        __block NSNumber *requestPlaying;
        __block EONASystemMediaSnapshot *requestSnapshot;

        void (^finish)(BOOL) = ^(BOOL timedOut) {
            if (finished || (!timedOut && (!infoDone || !playingDone || !pidDone || !commandsDone || !requestDone))) return;
            finished = YES;
            snapshot.title = textValue(information, "kMRMediaRemoteNowPlayingInfoTitle")
                ?: textValue(requestInformation, "kMRMediaRemoteNowPlayingInfoTitle");
            snapshot.artist = textValue(information, "kMRMediaRemoteNowPlayingInfoArtist")
                ?: textValue(requestInformation, "kMRMediaRemoteNowPlayingInfoArtist");
            snapshot.artwork = artworkValue(information) ?: artworkValue(requestInformation);
            // false sans identité ni métadonnées peut être refus de lecture, pas pause.
            NSNumber *identifiedPlaying = playingFromInfo(information) ?: playingFromInfo(requestInformation) ?: requestPlaying;
            snapshot.playingReliable = identifiedPlaying != nil;
            snapshot.playing = identifiedPlaying
                ?: ((information.count || legacyPlaying.boolValue) ? legacyPlaying : nil);
            if (snapshot.processIdentifier.intValue == NSProcessInfo.processInfo.processIdentifier) {
                snapshot.playing = nil;
                snapshot.playingReliable = NO;
            }
            if (!snapshot.commands && requestSnapshot.commands) {
                snapshot.commands = requestSnapshot.commands;
                snapshot.forwardInterval = requestSnapshot.forwardInterval;
                snapshot.backwardInterval = requestSnapshot.backwardInterval;
            }
            completion(snapshot);
        };
        if (readInfo) {
            readInfo(dispatch_get_main_queue(), ^(CFDictionaryRef raw) {
                NSDictionary *copy = raw ? [(__bridge NSDictionary *)raw copy] : nil;
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (finished) return;
                    information = [copy isKindOfClass:NSDictionary.class] ? copy : nil;
                    infoDone = YES;
                    finish(NO);
                });
            });
        }
        if (readPlaying) {
            readPlaying(dispatch_get_main_queue(), ^(Boolean value) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (finished) return;
                    legacyPlaying = @(value != 0);
                    playingDone = YES;
                    finish(NO);
                });
            });
        }
        if (readPID) {
            readPID(dispatch_get_main_queue(), ^(int processIdentifier) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (finished) return;
                    snapshot.processIdentifier = processIdentifier > 0 ? @(processIdentifier) : nil;
                    pidDone = YES;
                    finish(NO);
                });
            });
        }
        if (!commandsDone) {
            readCommands(localOrigin(), dispatch_get_main_queue(), ^(CFArrayRef raw) {
                NSArray *copy = raw ? [(__bridge NSArray *)raw copy] : nil;
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (finished) return;
                    applyCommands(snapshot, copy);
                    commandsDone = YES;
                    finish(NO);
                });
            });
        }
        if (!requestDone) {
            requestBusy = YES;
            // Getters synchrones facultatifs : jamais sur thread interface.
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                Class<EONANowPlayingRequest> request = (Class<EONANowPlayingRequest>)NSClassFromString(@"MRNowPlayingRequest");
                id<EONAContentItem> item = [request respondsToSelector:@selector(localNowPlayingItem)] ? [request localNowPlayingItem] : nil;
                id rawInfo = [item respondsToSelector:@selector(nowPlayingInfo)] ? [item nowPlayingInfo] : nil;
                NSDictionary *copy = [rawInfo isKindOfClass:NSDictionary.class] ? [rawInfo copy] : nil;
                id path = [request respondsToSelector:@selector(localNowPlayingPlayerPath)] ? [request localNowPlayingPlayerPath] : nil;
                NSNumber *playing;
                if ((item || path) && [request respondsToSelector:@selector(localPlaybackState)]) {
                    uint32_t state = [request localPlaybackState];
                    if (state >= 1 && state <= 4) playing = @(state == 1);
                }
                NSArray *commands = [request respondsToSelector:@selector(localSupportedCommands)] ? [request localSupportedCommands] : nil;
                EONASystemMediaSnapshot *fallback = [EONASystemMediaSnapshot new];
                applyCommands(fallback, commands);
                dispatch_async(dispatch_get_main_queue(), ^{
                    requestBusy = NO;
                    if (finished) return;
                    requestInformation = copy;
                    requestPlaying = playing;
                    requestSnapshot = fallback;
                    requestDone = YES;
                    finish(NO);
                });
            });
        }
        finish(NO);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ finish(YES); });
    });
#else
    dispatch_async(dispatch_get_main_queue(), ^{ completion([EONASystemMediaSnapshot new]); });
#endif
}

+ (void)beginObserving:(void (^)(EONASystemMediaSnapshot *, BOOL))changed {
#if EONA_EXPERIMENTAL_SYSTEM_MEDIA
    [self endObserving];
    loadMediaRemote();
    NSMutableArray *observers = [NSMutableArray array];
    const char *names[] = {
        "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
        "kMRMediaRemoteNowPlayingPlaybackQueueDidChangeNotification",
    };
    for (NSUInteger index = 0; index < sizeof(names) / sizeof(names[0]); index++) {
        NSString *name = mediaKey(names[index]) ?: @(names[index]);
        id observer = [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
            usingBlock:^(NSNotification *note) {
                NSDictionary *info = [note.userInfo isKindOfClass:NSDictionary.class] ? note.userInfo : nil;
                NSNumber *processIdentifier = notificationPID(info);
                if (processIdentifier.intValue == NSProcessInfo.processInfo.processIdentifier) return;
                EONASystemMediaSnapshot *event = [EONASystemMediaSnapshot new];
                event.processIdentifier = processIdentifier;
                event.playing = notificationPlaying(info);
                event.playingReliable = event.playing != nil;
                event.title = textValue(info, "kMRMediaRemoteNowPlayingInfoTitle");
                event.artist = textValue(info, "kMRMediaRemoteNowPlayingInfoArtist");
                event.artwork = artworkValue(info);
                NSString *applicationName = mediaKey("kMRMediaRemoteNowPlayingApplicationDidChangeNotification")
                    ?: @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification";
                changed(event, [note.name isEqualToString:applicationName]);
            }];
        [observers addObject:observer];
    }
    notificationObservers = observers;
    if (registerNotifications) registerNotifications(dispatch_get_main_queue());
#endif
}

+ (void)endObserving {
#if EONA_EXPERIMENTAL_SYSTEM_MEDIA
    for (id observer in notificationObservers) [NSNotificationCenter.defaultCenter removeObserver:observer];
    if (notificationObservers && unregisterNotifications) unregisterNotifications();
    notificationObservers = nil;
#endif
}

@end
