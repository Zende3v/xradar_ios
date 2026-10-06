#import "EONASystemMedia.h"
#import <dispatch/dispatch.h>

#if EONA_EXPERIMENTAL_SYSTEM_MEDIA
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>

// ABI vérifiée dans theos/headers/MediaRemote/MediaRemote.h. Framework privé, IPA interne uniquement.
typedef Boolean (*EONASendCommand)(int command, NSDictionary *userInfo);
typedef void (*EONAReadInfo)(dispatch_queue_t queue, void (^completion)(CFDictionaryRef information));
typedef void (*EONAReadPlaying)(dispatch_queue_t queue, void (^completion)(Boolean playing));

static void *mediaHandle;
static EONASendCommand sendCommand;
static EONAReadInfo readInfo;
static EONAReadPlaying readPlaying;

static void loadMediaRemote(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Conservé chargé pendant toute vie du process : callbacks peuvent arriver tard.
        mediaHandle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LOCAL | RTLD_LAZY);
        if (!mediaHandle) return;
        sendCommand = (EONASendCommand)dlsym(mediaHandle, "MRMediaRemoteSendCommand");
        readInfo = (EONAReadInfo)dlsym(mediaHandle, "MRMediaRemoteGetNowPlayingInfo");
        readPlaying = (EONAReadPlaying)dlsym(mediaHandle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    });
}

static NSString *infoKey(const char *name) {
    CFStringRef *key = mediaHandle ? (CFStringRef *)dlsym(mediaHandle, name) : NULL;
    return key && *key ? (__bridge NSString *)*key : nil;
}

static NSString *textValue(NSDictionary *info, const char *name) {
    NSString *key = infoKey(name);
    id value = key ? info[key] : nil;
    return [value isKindOfClass:NSString.class] && [value length] > 0 ? [value copy] : nil;
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
    return sendCommand != NULL;
#else
    return NO;
#endif
}

+ (BOOL)send:(EONASystemMediaCommand)command {
#if EONA_EXPERIMENTAL_SYSTEM_MEDIA
    if (![self prepare]) return NO;
    if (command != EONASystemMediaCommandToggle && command != EONASystemMediaCommandNext && command != EONASystemMediaCommandPrevious) return NO;
    // Retour confirme envoi seulement. État affiché vient des relevés, jamais du clic.
    return sendCommand((int)command, nil) != 0;
#else
    return NO;
#endif
}

+ (void)read:(void (^)(NSString *, NSString *, NSData *, NSNumber *))completion {
#if EONA_EXPERIMENTAL_SYSTEM_MEDIA
    loadMediaRemote();
    dispatch_async(dispatch_get_main_queue(), ^{
        __block BOOL infoDone = readInfo == NULL;
        __block BOOL playingDone = readPlaying == NULL;
        __block BOOL finished = NO;
        __block NSDictionary *information = nil;
        __block NSNumber *playing = nil;
        void (^finish)(BOOL) = ^(BOOL timedOut) {
            if (finished || (!timedOut && (!infoDone || !playingDone))) return;
            finished = YES;
            NSString *artworkKey = infoKey("kMRMediaRemoteNowPlayingInfoArtworkData");
            id artwork = artworkKey ? information[artworkKey] : nil;
            // Métadonnées locales uniquement. Taille limitée avant décodage image.
            if (![artwork isKindOfClass:NSData.class] || [artwork length] > 8 * 1024 * 1024) artwork = nil;
            completion(textValue(information, "kMRMediaRemoteNowPlayingInfoTitle"),
                       textValue(information, "kMRMediaRemoteNowPlayingInfoArtist"), artwork, playing);
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
                    playing = @(value != 0);
                    playingDone = YES;
                    finish(NO);
                });
            });
        }
        finish(NO);
        // Callback absent ou refus système : UI ne reste pas en chargement.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ finish(YES); });
    });
#else
    dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, nil, nil, nil); });
#endif
}

@end
