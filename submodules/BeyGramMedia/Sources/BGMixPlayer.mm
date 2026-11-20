#import "BeyGramMedia/BGMixPlayer.h"

#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>

#include <cmath>
#include <cstring>
#include <filesystem>
#include <functional>
#include <memory>
#include <string>
#include <string_view>

#include "bgmedia/audio/AudioData.hpp"
#include "bgmedia/audio/IPcmOutputTap.hpp"
#include "bgmedia/mix/MixEngine.hpp"
#include "bgmedia/mix/MixSession.hpp"
#include "BGMediaAVFoundationDecoder.hpp"
#include "BGMediaMixPreparation.hpp"
#include "BGMediaMixState.hpp"
#include "BGMixPcmTapSlot.hpp"

NSNotificationName const BGMixPlayerDidStartPlaybackNotification = @"BGMixPlayerDidStartPlaybackNotification";
NSNotificationName const BGMixPlayerDidStopForExternalAudioNotification = @"BGMixPlayerDidStopForExternalAudioNotification";

namespace {

constexpr uint32_t kSampleRate = 48000;
constexpr AVAudioFrameCount kScratchFrames = 4096;
// While the mix plays, observers get a new snapshot at most this often. In the background the timer that
// runs the update loop uses the same interval, because the display link does not fire there.
constexpr CFTimeInterval kObserverInterval = 0.1;
// The host tap (BG Wave). Attached and detached on the main thread, entered on the render thread.
using HostTapSlot = beygram::media::PcmTapSlot<bgmedia::IPcmOutputTap>;

NSString *stringFromUTF8(const std::string &text) {
    NSString *value = [NSString stringWithUTF8String:text.c_str()];
    return value ?: @"";
}

BOOL objectsEqual(id _Nullable a, id _Nullable b) {
    return a == b || [a isEqual:b];
}

BGMixTrackState trackStateFromQueue(bgmedia::mix::QueueState state) {
    switch (state) {
        case bgmedia::mix::QueueState::Pending: return BGMixTrackStatePending;
        case bgmedia::mix::QueueState::Preparing: return BGMixTrackStatePreparing;
        case bgmedia::mix::QueueState::Ready: return BGMixTrackStateReady;
        case bgmedia::mix::QueueState::Playing: return BGMixTrackStatePlaying;
        case bgmedia::mix::QueueState::Played: return BGMixTrackStatePlayed;
        case bgmedia::mix::QueueState::Failed: return BGMixTrackStateFailed;
    }
    return BGMixTrackStatePending;
}

BGMixTransport transportFromCore(beygram::media::MixTransport transport) {
    switch (transport) {
        case beygram::media::MixTransport::Stopped: return BGMixTransportStopped;
        case beygram::media::MixTransport::Playing: return BGMixTransportPlaying;
        case beygram::media::MixTransport::Paused: return BGMixTransportPaused;
    }
    return BGMixTransportStopped;
}

BGMixTrack *trackWithIdentifier(NSArray<BGMixTrack *> *queue, uint64_t identifier) {
    if (identifier == 0) {
        return nil;
    }
    for (BGMixTrack *track in queue) {
        if (track.identifier == identifier) {
            return track;
        }
    }
    return nil;
}

} // namespace

@interface BGMixTrack ()
@property (nonatomic, readwrite) uint64_t identifier;
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, copy) NSURL *fileURL;
@property (nonatomic, readwrite) BGMixTrackState state;
@property (nonatomic, readwrite) float progress;
@property (nonatomic, readwrite) NSTimeInterval duration;
@property (nonatomic, readwrite) double bpm;
@property (nonatomic, readwrite, nullable, copy) NSString *error;
@end

@implementation BGMixTrack

- (BOOL)isEqual:(id)object {
    if (self == object) {
        return YES;
    }
    if (![object isKindOfClass:[BGMixTrack class]]) {
        return NO;
    }
    BGMixTrack *other = object;
    return self.identifier == other.identifier && self.state == other.state &&
           self.progress == other.progress && self.duration == other.duration && self.bpm == other.bpm &&
           objectsEqual(self.name, other.name) && objectsEqual(self.fileURL, other.fileURL) &&
           objectsEqual(self.error, other.error);
}

- (NSUInteger)hash {
    return (NSUInteger)self.identifier ^ (NSUInteger)self.state;
}

@end

@interface BGMixSnapshot ()
@property (nonatomic, readwrite) BGMixTransport transport;
@property (nonatomic, readwrite, nullable) BGMixTrack *currentTrack;
@property (nonatomic, readwrite) NSTimeInterval position;
@property (nonatomic, readwrite) NSTimeInterval duration;
@property (nonatomic, readwrite, nullable) BGMixTrack *nextTrack;
@property (nonatomic, readwrite) BOOL transitionActive;
@property (nonatomic, readwrite) float transitionProgress;
@property (nonatomic, readwrite) BOOL preparingNext;
@property (nonatomic, readwrite, copy) NSArray<BGMixTrack *> *queue;
@property (nonatomic, readwrite, nullable, copy) NSString *lastError;
@end

@implementation BGMixSnapshot

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        _queue = @[];
    }
    return self;
}

- (BOOL)isEqualToSnapshot:(BGMixSnapshot *)other {
    if (other == nil) {
        return NO;
    }
    return self.transport == other.transport && objectsEqual(self.currentTrack, other.currentTrack) &&
           self.position == other.position && self.duration == other.duration &&
           objectsEqual(self.nextTrack, other.nextTrack) && self.transitionActive == other.transitionActive &&
           self.transitionProgress == other.transitionProgress && self.preparingNext == other.preparingNext &&
           [self.queue isEqualToArray:other.queue] && objectsEqual(self.lastError, other.lastError);
}

@end

@interface BGMixPlayer () {
    // Declaration order matters: the session must be destroyed before the engine.
    std::unique_ptr<bgmedia::mix::MixEngine> _engine;
    std::unique_ptr<bgmedia::mix::MixSession> _session;
    std::unique_ptr<HostTapSlot> _hostTap;
    float *_scratch;
}
@property (nonatomic, strong) AVAudioEngine *audioEngine;
@property (nonatomic, strong) AVAudioSourceNode *sourceNode;
@property (nonatomic, strong) AVAudioFormat *renderFormat;
@property (nonatomic, strong, nullable) CADisplayLink *displayLink;
// Drives the update loop in the background while the mix sounds. Nil in the foreground.
@property (nonatomic, strong, nullable) NSTimer *backgroundTimer;
@property (nonatomic) BOOL inBackground;
// Set when an interruption pauses a sounding mix. The end of the interruption may resume it.
@property (nonatomic) BOOL resumeAfterInterruption;
// The system's last refusal to start audio. Reported as lastError until a start succeeds.
@property (nonatomic, copy, nullable) NSString *audioError;
// Tokens of the notification observers. invalidate removes them.
@property (nonatomic, strong) NSMutableArray *notificationTokens;
// Weak references: an observer that goes away is dropped without a call.
@property (nonatomic, strong) NSHashTable<id<BGMixPlayerObserver>> *observers;
@property (nonatomic, strong, nullable) BGMixSnapshot *publishedSnapshot;
@property (nonatomic) CFTimeInterval lastPublishTime;
@property (nonatomic) BOOL publishing;
@end

@implementation BGMixPlayer

+ (NSURL *)mixDirectory {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray<NSURL *> *documents = [fileManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
    NSURL *directory = [documents.firstObject URLByAppendingPathComponent:@"bgmix" isDirectory:YES];
    [fileManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil];
    return directory;
}

static BGMixPlayer *sSharedPlayer = nil;

+ (BGMixPlayer *)sharedPlayer {
    // The app has one player. It is created on the first call, which happens on the main thread.
    if (sSharedPlayer == nil) {
        NSURL *cacheDirectory = [[self mixDirectory] URLByAppendingPathComponent:@"cache" isDirectory:YES];
        [[NSFileManager defaultManager] createDirectoryAtURL:cacheDirectory
                                 withIntermediateDirectories:YES
                                                  attributes:nil
                                                       error:nil];
        sSharedPlayer = [[BGMixPlayer alloc] initWithCacheDirectory:cacheDirectory.path];
    }
    return sSharedPlayer;
}

+ (void)stopSharedEngineIfRunning {
    if (sSharedPlayer != nil && ([sSharedPlayer isSounding] || sSharedPlayer.audioEngine.isRunning)) {
        [[NSNotificationCenter defaultCenter] postNotificationName:BGMixPlayerDidStopForExternalAudioNotification object:sSharedPlayer];
        [sSharedPlayer stopEngine];
    }
}

- (instancetype)initWithCacheDirectory:(NSString *)cacheDirectory {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _scratch = (float *)calloc((size_t)kScratchFrames * 2, sizeof(float));
    _engine = std::make_unique<bgmedia::mix::MixEngine>(kSampleRate);
    _hostTap = std::make_unique<HostTapSlot>();
    self.observers = [NSHashTable weakObjectsHashTable];
    self.notificationTokens = [NSMutableArray array];
    self.managesAudioSession = YES;

    beygram::media::MixPreparationOptions options;
    options.cacheDirectory = std::filesystem::path(cacheDirectory.UTF8String ?: "");
    options.useCache = !options.cacheDirectory.empty();
    options.targetSampleRate = kSampleRate;
    // Same admission budget as the Android bridge: a track, one preparation, and their session total.
    _session = std::make_unique<bgmedia::mix::MixSession>(
        *_engine,
        [options](const std::filesystem::path &path, bgmedia::mix::PreparedMixTrack &out,
                  std::string &error, std::function<void(float, std::string_view)> progress) {
            return beygram::media::prepareMixTrack(path, beygram::media::decodeWithAVFoundation, options, out, error, progress);
        },
        bgmedia::mix::MixPlanner{},
        bgmedia::mix::MixPcmBudget{beygram::media::kMixMaxTrackPcmBytes,
                                   beygram::media::kMixPreparationPcmReserve,
                                   beygram::media::kMixSessionPcmBudget});

    self.renderFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:kSampleRate channels:2];
    AVAudioFormat *format = self.renderFormat;
    bgmedia::mix::MixEngine *engine = _engine.get();
    float *scratch = _scratch;
    HostTapSlot *hostTap = _hostTap.get();
    // The render block must not capture self: it runs on the realtime thread.
    // It only touches the engine and the preallocated scratch buffer.
    self.sourceNode = [[AVAudioSourceNode alloc] initWithFormat:format
                                                    renderBlock:^OSStatus(BOOL *isSilence,
                                                                          const AudioTimeStamp *timestamp,
                                                                          AVAudioFrameCount frameCount,
                                                                          AudioBufferList *outputData) {
        (void)timestamp;
        AVAudioFrameCount done = 0;
        while (done < frameCount) {
            const AVAudioFrameCount chunk = MIN(frameCount - done, kScratchFrames);
            engine->render(scratch, (size_t)chunk);
            // The host tap gets the mix as it is rendered: the same interleaved buffer that goes to the output.
            if (bgmedia::IPcmOutputTap *tap = hostTap->enter()) {
                tap->onPcmRendered(scratch, (size_t)chunk, kSampleRate);
            }
            hostTap->leave();
            if (outputData->mNumberBuffers >= 2) {
                float *left = (float *)outputData->mBuffers[0].mData + done;
                float *right = (float *)outputData->mBuffers[1].mData + done;
                for (AVAudioFrameCount i = 0; i < chunk; ++i) {
                    left[i] = scratch[2 * i];
                    right[i] = scratch[2 * i + 1];
                }
            } else if (outputData->mNumberBuffers == 1) {
                float *dst = (float *)outputData->mBuffers[0].mData + 2 * done;
                std::memcpy(dst, scratch, (size_t)chunk * 2 * sizeof(float));
            }
            done += chunk;
        }
        *isSilence = NO;
        return noErr;
    }];

    self.audioEngine = [[AVAudioEngine alloc] init];
    [self.audioEngine attachNode:self.sourceNode];
    [self.audioEngine connect:self.sourceNode to:self.audioEngine.mainMixerNode format:format];

    [self observeSystemEvents];

    // The session's update() must run on the main thread once per frame.
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

    return self;
}

// Interruptions, route changes, engine restarts and the app's move to the background and back come from
// the system. They are delivered on the main queue, like every other call to the player. The blocks hold
// the player weakly; invalidate removes them.
- (void)observeSystemEvents {
    __weak BGMixPlayer *weakSelf = self;
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    NSOperationQueue *queue = [NSOperationQueue mainQueue];
    [self.notificationTokens addObject:[center addObserverForName:AVAudioSessionInterruptionNotification
                                                            object:nil
                                                             queue:queue
                                                        usingBlock:^(NSNotification *note) {
        [weakSelf handleInterruption:note];
    }]];
    [self.notificationTokens addObject:[center addObserverForName:AVAudioSessionRouteChangeNotification
                                                            object:nil
                                                             queue:queue
                                                        usingBlock:^(NSNotification *note) {
        [weakSelf handleRouteChange:note];
    }]];
    [self.notificationTokens addObject:[center addObserverForName:AVAudioEngineConfigurationChangeNotification
                                                            object:self.audioEngine
                                                             queue:queue
                                                        usingBlock:^(NSNotification *note) {
        [weakSelf handleEngineConfigurationChange];
    }]];
    [self.notificationTokens addObject:[center addObserverForName:UIApplicationDidEnterBackgroundNotification
                                                            object:nil
                                                             queue:queue
                                                        usingBlock:^(NSNotification *note) {
        [weakSelf enterBackground];
    }]];
    [self.notificationTokens addObject:[center addObserverForName:UIApplicationWillEnterForegroundNotification
                                                            object:nil
                                                             queue:queue
                                                        usingBlock:^(NSNotification *note) {
        [weakSelf enterForeground];
    }]];
}

- (void)dealloc {
    [self invalidate];
    free(_scratch);
    _scratch = nullptr;
}

// Runs the update loop: from the display link in the foreground, from backgroundTimer in the background.
- (void)tick:(id)sender {
    (void)sender;
    if (!_session) {
        return;
    }
    _session->update();
    if (CACurrentMediaTime() - self.lastPublishTime >= kObserverInterval) {
        [self publishSnapshotIfChanged];
    }
    [self updateBackgroundActivity];
}

- (BOOL)isSounding {
    if (!_session) {
        return NO;
    }
    return beygram::media::transportOf(_session->snapshot().engine) == beygram::media::MixTransport::Playing;
}

// Activates the audio session (unless the session manager does, see managesAudioSession) and starts the engine
// unless they run already. Returns NO, with audioError set, when the system refuses; the mix then does not start.
- (BOOL)ensureEngineRunning {
    if (self.audioEngine.isRunning) {
        return YES;
    }
    NSError *error = nil;
    if (self.managesAudioSession) {
        AVAudioSession *session = [AVAudioSession sharedInstance];
        if (![session setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault options:0 error:&error] ||
            ![session setActive:YES error:&error]) {
            self.audioError = error != nil
                ? [NSString stringWithFormat:@"Audio session error (%@:%ld).", error.domain ?: @"unknown", (long)error.code]
                : @"The audio session is not available.";
            return NO;
        }
    }
    [self.audioEngine prepare];
    if (![self.audioEngine startAndReturnError:&error]) {
        self.audioError = error != nil
            ? [NSString stringWithFormat:@"Audio engine error (%@:%ld).", error.domain ?: @"unknown", (long)error.code]
            : @"The audio engine did not start.";
        return NO;
    }
    self.audioError = nil;
    return YES;
}

// Sends the current snapshot to the observers when it differs from the last one sent. Nested calls
// (an observer that calls back into the player) are skipped; the next tick delivers their changes.
- (void)publishSnapshotIfChanged {
    if (self.publishing || !_session || self.observers.count == 0) {
        return;
    }
    self.lastPublishTime = CACurrentMediaTime();
    BGMixSnapshot *snapshot = self.snapshot;
    if (self.publishedSnapshot != nil && [snapshot isEqualToSnapshot:self.publishedSnapshot]) {
        return;
    }
    self.publishedSnapshot = snapshot;
    self.publishing = YES;
    @try {
        for (id<BGMixPlayerObserver> observer in self.observers.allObjects) {
            [observer mixPlayer:self didUpdateSnapshot:snapshot];
        }
    } @finally {
        self.publishing = NO;
    }
}

// Every command ends here. The background driver follows the transport, and observers hear about the
// change at once.
- (void)stateChanged {
    [self updateBackgroundActivity];
    [self publishSnapshotIfChanged];
}

// Chooses what drives the mix (BackgroundDrive in BGMediaMixState.hpp). The sounding check runs only in the
// background: in the foreground the display link runs every frame and nothing needs the check.
- (void)updateBackgroundActivity {
    if (!_session) {
        return;
    }
    const BOOL sounding = self.inBackground && [self isSounding];
    switch (beygram::media::backgroundDriveFor(self.inBackground, sounding)) {
        case beygram::media::BackgroundDrive::DisplayLink:
            [self stopBackgroundTimer];
            break;
        case beygram::media::BackgroundDrive::Timer:
            [self startBackgroundTimer];
            break;
        case beygram::media::BackgroundDrive::StopEngine:
            [self stopBackgroundTimer];
            if (self.audioEngine.isRunning) {
                [self.audioEngine stop];
            }
            break;
    }
}

- (void)startBackgroundTimer {
    if (self.backgroundTimer != nil) {
        return;
    }
    self.backgroundTimer = [NSTimer timerWithTimeInterval:kObserverInterval
                                                   target:self
                                                 selector:@selector(tick:)
                                                 userInfo:nil
                                                  repeats:YES];
    // Common modes, so the timer keeps running while a scroll tracks.
    [[NSRunLoop mainRunLoop] addTimer:self.backgroundTimer forMode:NSRunLoopCommonModes];
}

- (void)stopBackgroundTimer {
    [self.backgroundTimer invalidate];
    self.backgroundTimer = nil;
}

- (void)enterBackground {
    self.inBackground = YES;
    [self updateBackgroundActivity];
}

- (void)enterForeground {
    self.inBackground = NO;
    [self updateBackgroundActivity];
}

// A call, Siri or another audio owner interrupts the mix. The system stops the engine itself, so the mix
// pauses, and the end of the interruption resumes it only when it was sounding and the system allows.
- (void)handleInterruption:(NSNotification *)note {
    NSNumber *type = note.userInfo[AVAudioSessionInterruptionTypeKey];
    if (type == nil) {
        return;
    }
    if (type.unsignedIntegerValue == AVAudioSessionInterruptionTypeBegan) {
        self.resumeAfterInterruption = [self isSounding];
        [self pause];
        return;
    }
    NSNumber *options = note.userInfo[AVAudioSessionInterruptionOptionKey];
    const BOOL systemAllowsResume = (options.unsignedIntegerValue & AVAudioSessionInterruptionOptionShouldResume) != 0;
    const BOOL resume = beygram::media::resumesAfterInterruption(self.resumeAfterInterruption, systemAllowsResume);
    self.resumeAfterInterruption = NO;
    // A session owned by the app's session manager is resumed by its owner, not here.
    if (resume && self.managesAudioSession) {
        [self play];
    }
}

// Headphones or another output went away. The mix pauses rather than carry on through the speaker. Other
// route changes leave the state alone.
- (void)handleRouteChange:(NSNotification *)note {
    NSNumber *reason = note.userInfo[AVAudioSessionRouteChangeReasonKey];
    if (reason.unsignedIntegerValue == AVAudioSessionRouteChangeReasonOldDeviceUnavailable && [self isSounding]) {
        [self pause];
    }
}

// The system stopped the engine, and the hardware format may have changed. Connect the graph again with the
// format the source node renders, then start the engine if the mix is sounding. If the system refuses, the
// mix pauses and lastError says why.
- (void)handleEngineConfigurationChange {
    if (!_session) {
        return;
    }
    [self.audioEngine connect:self.sourceNode to:self.audioEngine.mainMixerNode format:self.renderFormat];
    if ([self isSounding] && ![self ensureEngineRunning]) {
        _session->pause();
    }
    [self stateChanged];
}

// The current state, read from the engine on each access.
- (BGMixSnapshot *)snapshot {
    BGMixSnapshot *snapshot = [[BGMixSnapshot alloc] init];
    if (!_session) {
        return snapshot;
    }
    const bgmedia::mix::MixSessionSnapshot core = _session->snapshot();

    NSMutableArray<BGMixTrack *> *queue = [NSMutableArray arrayWithCapacity:core.queue.size()];
    for (const bgmedia::mix::QueueItemStatus &item : core.queue) {
        BGMixTrack *track = [[BGMixTrack alloc] init];
        track.identifier = item.id;
        track.name = stringFromUTF8(item.displayName);
        track.fileURL = [NSURL fileURLWithPath:stringFromUTF8(item.path)];
        track.state = trackStateFromQueue(item.state);
        track.progress = item.progress;
        track.duration = item.durationSeconds;
        track.bpm = item.bpm;
        track.error = item.error.empty() ? nil : stringFromUTF8(item.error);
        [queue addObject:track];
    }

    const bgmedia::mix::MixSnapshot &engine = core.engine;
    snapshot.queue = queue;
    snapshot.transport = transportFromCore(beygram::media::transportOf(engine));
    snapshot.currentTrack = trackWithIdentifier(queue, beygram::media::currentTrackId(engine));
    snapshot.nextTrack = trackWithIdentifier(queue, beygram::media::nextTrackId(engine));
    snapshot.position = beygram::media::masterPositionSeconds(engine);
    snapshot.duration = beygram::media::masterDurationSeconds(engine);
    snapshot.transitionActive = _engine->transitionActive() ? YES : NO;
    snapshot.transitionProgress = (float)engine.transitionProgress;
    snapshot.preparingNext = core.preparingNext ? YES : NO;
    // The engine's own error wins. Otherwise the system's last refusal to start audio, if any.
    snapshot.lastError = core.lastError.empty() ? self.audioError : stringFromUTF8(core.lastError);
    return snapshot;
}

- (void)addObserver:(id<BGMixPlayerObserver>)observer {
    if (observer == nil || !_session) {
        return;
    }
    [self.observers addObject:observer];
    [observer mixPlayer:self didUpdateSnapshot:self.snapshot];
}

- (void)removeObserver:(id<BGMixPlayerObserver>)observer {
    if (observer != nil) {
        [self.observers removeObject:observer];
    }
}

- (void)resetDecksSynchronously {
    if (!_session || !_engine) {
        return;
    }
    if (self.audioEngine.isRunning) {
        [self.audioEngine stop];
    }
    _session->stopAll();
    // Safe on main thread because AVAudioEngine is stopped:
    // 1) 1024 frames drains the 8ms de-click ramp (384 frames at 48kHz) and handles stopRequested_.
    // 2) 1 frame enters the paused&&pauseFade_<=0 path and marks both decks playing=false.
    _engine->render(_scratch, 1024);
    _engine->render(_scratch, 1);
    _session->clearQueue();
    _session->update();
    // 3) Advance renderEpoch_ once more so retired PCM buffers from cleared decks are reclaimed immediately.
    _engine->render(_scratch, 1);
    _session->update();
}

- (void)setPcmTap:(nullable void *)tap {
    if (_hostTap) {
        _hostTap->set(static_cast<bgmedia::IPcmOutputTap *>(tap));
    }
}

- (uint64_t)addTrackAtURL:(NSURL *)url {
    const char *utf8Path = url.path.UTF8String;
    if (!url.isFileURL || utf8Path == nullptr || !_session) {
        return 0;
    }
    const uint64_t identifier = _session->addTrack(std::filesystem::path(utf8Path));
    [self stateChanged];
    return identifier;
}

- (uint64_t)replaceQueueAndPlayTrackAtURL:(NSURL *)url {
    const char *utf8Path = url.path.UTF8String;
    if (!url.isFileURL || utf8Path == nullptr || !_session || !_engine) {
        return 0;
    }
    [self resetDecksSynchronously];
    const uint64_t identifier = _session->addTrack(std::filesystem::path(utf8Path));
    if (identifier != 0 && [self ensureEngineRunning]) {
        if (self.managesAudioSession) {
            [[NSNotificationCenter defaultCenter] postNotificationName:BGMixPlayerDidStartPlaybackNotification object:self];
        }
        _session->play();
    }
    [self stateChanged];
    return identifier;
}

- (BOOL)removeTrackWithIdentifier:(uint64_t)identifier {
    if (!_session) {
        return NO;
    }
    const bool removed = _session->removeTrack(identifier);
    [self stateChanged];
    return removed ? YES : NO;
}

- (void)clearQueue {
    if (_session && _engine) {
        if (!self.audioEngine.isRunning) {
            _engine->render(_scratch, 1024);
            _engine->render(_scratch, 1);
        }
        _session->clearQueue();
        _session->update();
        if (!self.audioEngine.isRunning) {
            _engine->render(_scratch, 1);
            _session->update();
        }
    }
    [self stateChanged];
}

// The engine starts first. If the system refuses, the mix does not start and lastError says why.
- (void)play {
    if (_session && [self ensureEngineRunning]) {
        if (self.managesAudioSession) {
            [[NSNotificationCenter defaultCenter] postNotificationName:BGMixPlayerDidStartPlaybackNotification object:self];
        }
        _session->play();
    }
    [self stateChanged];
}

- (void)pause {
    if (_session) {
        _session->pause();
    }
    [self stateChanged];
}

// The session manager calls this when it takes the session away: the mix pauses and the engine stops, so that
// no engine keeps running on a session that is no longer ours.
- (void)stopEngine {
    [self pause];
    if (self.audioEngine.isRunning) {
        [self.audioEngine stop];
    }
}

- (void)next {
    if (_session && [self ensureEngineRunning]) {
        _session->next();
    }
    [self stateChanged];
}

- (BOOL)tryStartNextTransition {
    if (!_session || !_engine) {
        return NO;
    }
    if (_engine->transitionActive()) {
        return NO;
    }
    BGMixSnapshot *before = self.snapshot;
    if (before.nextTrack == nil || before.nextTrack.state != BGMixTrackStateReady) {
        return NO;
    }
    if (![self ensureEngineRunning]) {
        [self stateChanged];
        return NO;
    }
    _session->next();
    const BOOL started = _engine->transitionActive() ? YES : NO;
    if (!started) {
        // Clear pending nextRequested_ when the planner rejected the transition so serviceDecks()
        // does not keep retrying and emitting "transition plan is not valid" on every tick.
        _session->cancelTransition();
    }
    [self stateChanged];
    return started;
}

- (void)stopAll {
    if (_session && _engine) {
        if (self.audioEngine.isRunning) {
            [self.audioEngine stop];
        }
        _session->stopAll();
        _engine->render(_scratch, 1024);
        _engine->render(_scratch, 1);
    }
    [self stateChanged];
}

- (BOOL)seekToPosition:(NSTimeInterval)seconds {
    if (!_session || !std::isfinite(seconds) || seconds < 0.0) {
        return NO;
    }
    const bool moved = _session->seekDeck(_session->snapshot().engine.master, seconds);
    [self stateChanged];
    return moved ? YES : NO;
}

- (BOOL)isTransitionActive {
    return _engine && _engine->transitionActive() ? YES : NO;
}

- (void)setTransitionDuration:(double)seconds {
    if (_session) {
        _session->setTransitionDuration(seconds);
    }
}

- (void)setAdaptiveTransitions:(BOOL)enabled {
    if (_session) {
        _session->setAdaptive(enabled);
    }
}

- (void)setBassSwap:(BOOL)enabled {
    if (_session) {
        _session->setBassSwap(enabled);
    }
}

- (void)invalidate {
    // Detach first: once the engine stops, no render call can reach the tap any more.
    [self setPcmTap:NULL];
    [self.displayLink invalidate];
    self.displayLink = nil;
    [self stopBackgroundTimer];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    for (id token in self.notificationTokens) {
        [center removeObserver:token];
    }
    [self.notificationTokens removeAllObjects];
    [self.observers removeAllObjects];
    self.publishedSnapshot = nil;
    self.resumeAfterInterruption = NO;
    if (_session) {
        _session->stopAll();
    }
    _session.reset();
    // The render block reads the engine, so the audio engine stops before the engine is destroyed.
    if (self.audioEngine.isRunning) {
        [self.audioEngine stop];
    }
    _engine.reset();
}

@end
