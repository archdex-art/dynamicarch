// DynamicArch media bridge.
//
// Loaded into /usr/bin/perl (an Apple platform binary) so that MediaRemote is
// reachable on macOS 15.4+. Speaks newline-delimited JSON:
//
//   stdout  {"type":"now", ...}     full now-playing state, on every change
//           {"type":"gone"}         nothing is playing any more
//           {"type":"ready"}        bridge is live
//   stdin   {"cmd":"toggle"}        play/pause, next, previous, seek, ...
//
// Unlike the one-shot helpers other apps use, this process is long lived and
// bidirectional: commands execute in the already-warm process, so a play/pause
// tap costs microseconds instead of a process spawn.

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <dlfcn.h>

typedef void (*MRRegisterFn)(dispatch_queue_t);
typedef void (*MRGetInfoFn)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*MRGetIsPlayingFn)(dispatch_queue_t, void (^)(Boolean));
typedef void (*MRGetPIDFn)(dispatch_queue_t, void (^)(int));
typedef Boolean (*MRSendCommandFn)(int, CFDictionaryRef);
typedef void (*MRSetElapsedFn)(double);
typedef void (*MRSetShuffleFn)(int);
typedef void (*MRSetRepeatFn)(int);
typedef void (*MRSetSpeedFn)(float);

static MRRegisterFn mrRegister;
static MRGetInfoFn mrGetInfo;
static MRGetIsPlayingFn mrGetIsPlaying;
static MRGetPIDFn mrGetPID;
static MRSendCommandFn mrSendCommand;
static MRSetElapsedFn mrSetElapsed;
static MRSetShuffleFn mrSetShuffle;
static MRSetRepeatFn mrSetRepeat;
static MRSetSpeedFn mrSetSpeed;

static dispatch_queue_t gQueue;
static NSString *gArtworkFingerprint;
static NSString *gLastPayload;
static NSDate *gLastEmit;
static dispatch_source_t gDebounce;
// ARC will happily release a local dispatch source the moment it stops being
// referenced - even while it is resumed - which silently kills the timer. The
// long-lived sources are owned at file scope.
static dispatch_source_t gCommandSource;
static dispatch_source_t gHeartbeat;

static BOOL loadMediaRemote(void) {
    void *handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!handle) return NO;
    mrRegister = (MRRegisterFn)dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications");
    mrGetInfo = (MRGetInfoFn)dlsym(handle, "MRMediaRemoteGetNowPlayingInfo");
    mrGetIsPlaying = (MRGetIsPlayingFn)dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    mrGetPID = (MRGetPIDFn)dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPID");
    mrSendCommand = (MRSendCommandFn)dlsym(handle, "MRMediaRemoteSendCommand");
    mrSetElapsed = (MRSetElapsedFn)dlsym(handle, "MRMediaRemoteSetElapsedTime");
    mrSetShuffle = (MRSetShuffleFn)dlsym(handle, "MRMediaRemoteSetShuffleMode");
    mrSetRepeat = (MRSetRepeatFn)dlsym(handle, "MRMediaRemoteSetRepeatMode");
    mrSetSpeed = (MRSetSpeedFn)dlsym(handle, "MRMediaRemoteSetPlaybackSpeed");
    return mrRegister && mrGetInfo && mrSendCommand;
}

static void emit(NSDictionary *object) {
    // NSJSONSerialization *raises* for non-finite numbers rather than
    // returning nil, and the values below come from whatever app published
    // now-playing info. Unhandled, one NaN duration would kill the helper and
    // the supervisor would restart it into a permanent crash loop.
    if (![NSJSONSerialization isValidJSONObject:object]) return;
    NSData *data = nil;
    @try {
        NSError *error = nil;
        data = [NSJSONSerialization dataWithJSONObject:object options:0 error:&error];
    } @catch (NSException *exception) {
        fprintf(stderr, "serialization failed: %s\n", exception.reason.UTF8String);
        return;
    }
    if (!data) return;
    NSMutableData *line = [data mutableCopy];
    [line appendBytes:"\n" length:1];
    fwrite(line.bytes, 1, line.length, stdout);
    fflush(stdout);
}

static NSString *stringValue(id value) {
    if (!value || value == NSNull.null) return nil;
    if ([value isKindOfClass:NSString.class]) return value;
    return [value description];
}

static void buildPayload(NSDictionary *info, int pid, NSNumber *isPlaying) {
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"type"] = @"now";

    NSString *title = stringValue(info[@"kMRMediaRemoteNowPlayingInfoTitle"]);
    NSString *artist = stringValue(info[@"kMRMediaRemoteNowPlayingInfoArtist"]);
    NSString *album = stringValue(info[@"kMRMediaRemoteNowPlayingInfoAlbum"]);
    if (title) payload[@"title"] = title;
    if (artist) payload[@"artist"] = artist;
    if (album) payload[@"album"] = album;

    // Only finite numbers cross the wire; a player reporting NaN or infinity
    // simply omits the field instead of taking the helper down.
    void (^putNumber)(NSString *, id) = ^(NSString *key, id value) {
        if (![value isKindOfClass:NSNumber.class]) return;
        double resolved = [value doubleValue];
        if (!isfinite(resolved)) return;
        payload[key] = @(resolved);
    };
    putNumber(@"duration", info[@"kMRMediaRemoteNowPlayingInfoDuration"]);
    putNumber(@"elapsed", info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"]);
    putNumber(@"rate", info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"]);
    id rate = info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"];

    id timestamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
    if ([timestamp isKindOfClass:NSDate.class]) {
        payload[@"timestamp"] = @([(NSDate *)timestamp timeIntervalSince1970]);
    }

    id shuffle = info[@"kMRMediaRemoteNowPlayingInfoShuffleMode"];
    id repeatMode = info[@"kMRMediaRemoteNowPlayingInfoRepeatMode"];
    if (shuffle) payload[@"shuffle"] = @([shuffle intValue]);
    if (repeatMode) payload[@"repeat"] = @([repeatMode intValue]);

    BOOL playing = isPlaying ? isPlaying.boolValue : (rate ? [rate doubleValue] > 0.01 : NO);
    payload[@"playing"] = @(playing);

    if (pid > 0) {
        payload[@"pid"] = @(pid);
        NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
        if (app.bundleIdentifier) payload[@"bundleIdentifier"] = app.bundleIdentifier;
        if (app.localizedName) payload[@"appName"] = app.localizedName;
    }

    NSData *artwork = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
    if ([artwork isKindOfClass:NSData.class] && artwork.length > 0) {
        NSString *fingerprint = [NSString stringWithFormat:@"%lu-%lu",
                                 (unsigned long)artwork.length,
                                 (unsigned long)[artwork hash]];
        payload[@"artworkFingerprint"] = fingerprint;
        // Only ship the bytes when the image actually changed: artwork is
        // hundreds of kilobytes and changes far less often than progress.
        if (![fingerprint isEqualToString:gArtworkFingerprint]) {
            gArtworkFingerprint = fingerprint;
            payload[@"artwork"] = [artwork base64EncodedStringWithOptions:0];
            NSString *mime = stringValue(info[@"kMRMediaRemoteNowPlayingInfoArtworkMIMEType"]);
            if (mime) payload[@"artworkMime"] = mime;
        }
    } else if (gArtworkFingerprint) {
        gArtworkFingerprint = nil;
        payload[@"artworkCleared"] = @YES;
    }

    if (!title && !artist) {
        if (gLastPayload) {
            gLastPayload = nil;
            emit(@{@"type": @"gone"});
        }
        return;
    }

    // Suppress byte-identical repeats (MediaRemote is chatty).
    NSMutableDictionary *identity = [payload mutableCopy];
    [identity removeObjectForKey:@"artwork"];
    NSString *fingerprint = [identity description];
    if ([fingerprint isEqualToString:gLastPayload] && !payload[@"artwork"]) return;
    gLastPayload = fingerprint;

    emit(payload);
}

static void refresh(void) {
    if (!mrGetInfo) return;
    mrGetInfo(gQueue, ^(CFDictionaryRef raw) {
        NSDictionary *info = (__bridge NSDictionary *)raw;
        void (^withPID)(int) = ^(int pid) {
            if (mrGetIsPlaying) {
                mrGetIsPlaying(gQueue, ^(Boolean playing) {
                    buildPayload(info, pid, @(playing));
                });
            } else {
                buildPayload(info, pid, nil);
            }
        };
        if (mrGetPID) {
            mrGetPID(gQueue, ^(int pid) { withPID(pid); });
        } else {
            withPID(0);
        }
    });
}

static void scheduleRefresh(void) {
    // Coalesce bursts: MediaRemote fires several notifications per track change.
    if (gDebounce) dispatch_source_cancel(gDebounce);
    gDebounce = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, gQueue);
    dispatch_source_set_timer(gDebounce,
                              dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_MSEC),
                              DISPATCH_TIME_FOREVER, 10 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(gDebounce, ^{
        dispatch_source_cancel(gDebounce);
        gDebounce = nil;
        refresh();
    });
    dispatch_resume(gDebounce);
}

static void handleCommand(NSDictionary *command) {
    NSString *name = command[@"cmd"];
    if (![name isKindOfClass:NSString.class]) return;

    static NSDictionary *commandIDs;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        commandIDs = @{
            @"play": @0, @"pause": @1, @"toggle": @2, @"stop": @3,
            @"next": @4, @"previous": @5, @"toggleShuffle": @6, @"toggleRepeat": @7,
            @"beginFastForward": @8, @"endFastForward": @9,
            @"beginRewind": @10, @"endRewind": @11,
            @"back15": @12, @"forward15": @13,
            @"like": @0x6A, @"dislike": @0x6B,
        };
    });

    // Parameters are class-checked like the command name is: -doubleValue on
    // an array is an unrecognised selector, and this is a protocol parser.
    double (^number)(NSString *, double, double) = ^(NSString *key, double low, double high) {
        id value = command[key];
        if (![value isKindOfClass:NSNumber.class]) return (double)NAN;
        double resolved = [value doubleValue];
        if (!isfinite(resolved) || resolved < low || resolved > high) return (double)NAN;
        return resolved;
    };

    if ([name isEqualToString:@"seek"]) {
        double position = number(@"position", 0, 86400);
        if (!isnan(position) && mrSetElapsed) mrSetElapsed(position);
        scheduleRefresh();
        return;
    }
    if ([name isEqualToString:@"shuffle"]) {
        double mode = number(@"mode", 0, 16);
        if (!isnan(mode) && mrSetShuffle) mrSetShuffle((int)mode);
        scheduleRefresh();
        return;
    }
    if ([name isEqualToString:@"repeat"]) {
        double mode = number(@"mode", 0, 16);
        if (!isnan(mode) && mrSetRepeat) mrSetRepeat((int)mode);
        scheduleRefresh();
        return;
    }
    if ([name isEqualToString:@"speed"]) {
        double speed = number(@"speed", 0, 8);
        if (!isnan(speed) && mrSetSpeed) mrSetSpeed((float)speed);
        return;
    }
    if ([name isEqualToString:@"refresh"]) {
        gLastPayload = nil;
        gArtworkFingerprint = nil;
        refresh();
        return;
    }

    NSNumber *identifier = commandIDs[name];
    if (identifier && mrSendCommand) {
        mrSendCommand(identifier.intValue, NULL);
        scheduleRefresh();
    }
}

static void readCommands(void) {
    NSFileHandle *input = NSFileHandle.fileHandleWithStandardInput;
    gCommandSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ,
                                            input.fileDescriptor, 0, gQueue);
    dispatch_source_t source = gCommandSource;
    static NSMutableData *buffer;
    buffer = [NSMutableData data];
    dispatch_source_set_event_handler(source, ^{
        char chunk[4096];
        ssize_t count = read(input.fileDescriptor, chunk, sizeof(chunk));
        if (count <= 0) { exit(0); }
        [buffer appendBytes:chunk length:count];
        // A line that never terminates must not grow without bound.
        if (buffer.length > 1024 * 1024) {
            [buffer setLength:0];
            fprintf(stderr, "dropping oversized command line\n");
        }
        while (YES) {
            const char *bytes = buffer.bytes;
            NSUInteger newline = NSNotFound;
            for (NSUInteger i = 0; i < buffer.length; i++) {
                if (bytes[i] == '\n') { newline = i; break; }
            }
            if (newline == NSNotFound) break;
            NSData *line = [buffer subdataWithRange:NSMakeRange(0, newline)];
            [buffer replaceBytesInRange:NSMakeRange(0, newline + 1) withBytes:NULL length:0];
            if (line.length == 0) continue;
            NSDictionary *command = [NSJSONSerialization JSONObjectWithData:line options:0 error:NULL];
            if ([command isKindOfClass:NSDictionary.class]) handleCommand(command);
        }
    });
    dispatch_resume(source);
}

__attribute__((visibility("default")))
void arch_media_serve(void *cv, void *sp, int items) {
    @autoreleasepool {
        if (!loadMediaRemote()) {
            emit(@{@"type": @"error", @"message": @"MediaRemote unavailable"});
            exit(2);
        }
        gQueue = dispatch_queue_create("app.dynamicarch.media", DISPATCH_QUEUE_SERIAL);

        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        for (NSString *name in @[@"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                                 @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                                 @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification"]) {
            [center addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
                scheduleRefresh();
            }];
        }
        [NSWorkspace.sharedWorkspace.notificationCenter
            addObserverForName:NSWorkspaceDidTerminateApplicationNotification
                        object:nil queue:nil usingBlock:^(NSNotification *note) {
            scheduleRefresh();
        }];

        mrRegister(gQueue);
        readCommands();
        emit(@{@"type": @"ready"});
        refresh();

        // Periodic resync keeps elapsed time honest for players that do not
        // post notifications while scrubbing.
        gHeartbeat = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, gQueue);
        dispatch_source_t heartbeat = gHeartbeat;
        dispatch_source_set_timer(heartbeat, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC),
                                  5 * NSEC_PER_SEC, NSEC_PER_SEC / 2);
        dispatch_source_set_event_handler(heartbeat, ^{
            // If the app went away - including a hard kill, where stdin may
            // still be held open by an inherited descriptor - go with it. A
            // stray helper holding a MediaRemote registration is a leak.
            if (getppid() == 1) { exit(0); }
            refresh();
        });
        dispatch_resume(heartbeat);

        CFRunLoopRun();
    }
}

__attribute__((visibility("default")))
void arch_media_get(void *cv, void *sp, int items) {
    @autoreleasepool {
        if (!loadMediaRemote()) {
            emit(@{@"type": @"error", @"message": @"MediaRemote unavailable"});
            exit(2);
        }
        gQueue = dispatch_queue_create("app.dynamicarch.media.get", DISPATCH_QUEUE_SERIAL);
        refresh();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), gQueue, ^{ exit(0); });
        CFRunLoopRun();
    }
}
