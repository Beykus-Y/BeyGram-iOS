#import "BeyGramMedia/BGMixPlayer.h"

#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

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
#include "BGMediaMixPreparation.hpp"
#include "BGMediaMixState.hpp"
#include "BGMixPcmTapSlot.hpp"

namespace {

constexpr uint32_t kSampleRate = 48000;
constexpr AVAudioFrameCount kScratchFrames = 4096;
// While the player runs, observers get a new snapshot at most this often.
constexpr CFTimeInterval kObserverInterval = 0.1;
// The host tap (BG Wave). Attached and detached on the main thread, entered on the render thread.
using HostTapSlot = beygram::media::PcmTapSlot<bgmedia::IPcmOutputTap>;

// Decodes any file AVFoundation can read (MP3, AAC/M4A, FLAC, WAV, ALAC) into interleaved float PCM.
// Runs on the MixSession worker thread. The decoded size is known from the file length, so a track
// that would not fit the in-memory limit is refused before anything is allocated. The file is read in
// chunks into storage reserved once (no second full-length copy), and the checkpoint runs between
// chunks: a cancelled job throws out of here.
bool decodeWithAVFoundation(const std::filesystem::path &path, std::uint64_t maxDecodedBytes,
                            const beygram::media::MixCheckpoint &checkpoint,
                            bgmedia::AudioData &out, std::string &error) {
    constexpr AVAudioFrameCount kChunkFrames = 65536;
    AVAudioFile *file = nil;
    AVAudioPCMBuffer *buffer = nil;
    try {
        // The worker thread has no autorelease pool of its own. The pool is popped on the way out
        // of a C++ exception too, so the checkpoint may throw from inside it.
        @autoreleasepool {
            NSString *filePath = [NSString stringWithUTF8String:path.c_str()];
            if (filePath == nil) {
                error = "Invalid file path.";
                return false;
            }
            NSError *nsError = nil;
            file = [[AVAudioFile alloc] initForReading:[NSURL fileURLWithPath:filePath] error:&nsError];
            if (file == nil) {
                error = nsError.localizedDescription.UTF8String ?: "Could not open audio file.";
                return false;
            }
            AVAudioFormat *format = file.processingFormat; // float32, non-interleaved
            const AVAudioFramePosition length = file.length;
            if (length <= 0 || format.channelCount == 0) {
                error = "Audio file is empty.";
                return false;
            }
            const auto channels = static_cast<std::uint32_t>(format.channelCount);
            if (beygram::media::interleavedFloatBytes(static_cast<std::uint64_t>(length), channels) >
                maxDecodedBytes) {
                error = "decoded PCM exceeds the in-memory limit";
                return false;
            }
            buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:kChunkFrames];
            if (buffer == nil) {
                error = "Could not decode audio file.";
                return false;
            }
            beygram::media::InterleavedPcmBuilder builder(channels, static_cast<std::uint64_t>(length),
                                                          maxDecodedBytes);
            for (;;) {
                if (![file readIntoBuffer:buffer frameCount:kChunkFrames error:&nsError]) {
                    error = nsError.localizedDescription.UTF8String ?: "Could not decode audio file.";
                    return false;
                }
                const AVAudioFrameCount frames = buffer.frameLength;
                if (frames == 0) {
                    break;
                }
                builder.appendPlanar(buffer.floatChannelData, frames);
                checkpoint();
            }
            out.channels = channels;
            out.sampleRate = (uint32_t)format.sampleRate;
            out.samples = builder.take();
            return out.valid();
        }
    } catch (...) {
        // C++ exceptions do not release ARC references in this file, so drop them before rethrowing.
        buffer = nil;
        file = nil;
        throw;
    }
}

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
@property (nonatomic, strong, nullable) CADisplayLink *displayLink;
@property (nonatomic) BOOL engineStarted;
// Weak references: an observer that goes away is dropped without a call.
@property (nonatomic, strong) NSHashTable<id<BGMixPlayerObserver>> *observers;
@property (nonatomic, strong, nullable) BGMixSnapshot *publishedSnapshot;
@property (nonatomic) CFTimeInterval lastPublishTime;
@property (nonatomic) BOOL publishing;
@end

@implementation BGMixPlayer

- (instancetype)initWithCacheDirectory:(NSString *)cacheDirectory {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _scratch = (float *)calloc((size_t)kScratchFrames * 2, sizeof(float));
    _engine = std::make_unique<bgmedia::mix::MixEngine>(kSampleRate);
    _hostTap = std::make_unique<HostTapSlot>();
    self.observers = [NSHashTable weakObjectsHashTable];

    beygram::media::MixPreparationOptions options;
    options.cacheDirectory = std::filesystem::path(cacheDirectory.UTF8String ?: "");
    options.useCache = !options.cacheDirectory.empty();
    options.targetSampleRate = kSampleRate;
    // Same admission budget as the Android bridge: a track, one preparation, and their session total.
    _session = std::make_unique<bgmedia::mix::MixSession>(
        *_engine,
        [options](const std::filesystem::path &path, bgmedia::mix::PreparedMixTrack &out,
                  std::string &error, std::function<void(float, std::string_view)> progress) {
            return beygram::media::prepareMixTrack(path, decodeWithAVFoundation, options, out, error, progress);
        },
        bgmedia::mix::MixPlanner{},
        bgmedia::mix::MixPcmBudget{beygram::media::kMixMaxTrackPcmBytes,
                                   beygram::media::kMixPreparationPcmReserve,
                                   beygram::media::kMixSessionPcmBudget});

    AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:kSampleRate channels:2];
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

    // The session's update() must run on the main thread once per frame.
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

    return self;
}

- (void)dealloc {
    [self invalidate];
    free(_scratch);
    _scratch = nullptr;
}

- (void)tick:(CADisplayLink *)link {
    (void)link;
    if (!_session) {
        return;
    }
    _session->update();
    if (CACurrentMediaTime() - self.lastPublishTime >= kObserverInterval) {
        [self publishSnapshotIfChanged];
    }
}

- (void)ensureEngineRunning {
    if (self.engineStarted) {
        return;
    }
    AVAudioSession *session = AVAudioSession.sharedInstance;
    [session setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault options:0 error:nil];
    [session setActive:YES error:nil];
    NSError *error = nil;
    [self.audioEngine prepare];
    if ([self.audioEngine startAndReturnError:&error]) {
        self.engineStarted = YES;
    }
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
    snapshot.lastError = core.lastError.empty() ? nil : stringFromUTF8(core.lastError);
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
    [self publishSnapshotIfChanged];
    return identifier;
}

- (BOOL)removeTrackWithIdentifier:(uint64_t)identifier {
    if (!_session) {
        return NO;
    }
    const bool removed = _session->removeTrack(identifier);
    [self publishSnapshotIfChanged];
    return removed ? YES : NO;
}

- (void)clearQueue {
    if (_session) {
        _session->clearQueue();
    }
    [self publishSnapshotIfChanged];
}

- (void)play {
    [self ensureEngineRunning];
    if (_session) {
        _session->play();
    }
    [self publishSnapshotIfChanged];
}

- (void)pause {
    if (_session) {
        _session->pause();
    }
    [self publishSnapshotIfChanged];
}

- (void)next {
    [self ensureEngineRunning];
    if (_session) {
        _session->next();
    }
    [self publishSnapshotIfChanged];
}

- (void)stopAll {
    if (_session) {
        _session->stopAll();
    }
    [self publishSnapshotIfChanged];
}

- (BOOL)seekToPosition:(NSTimeInterval)seconds {
    if (!_session || !std::isfinite(seconds) || seconds < 0.0) {
        return NO;
    }
    const bool moved = _session->seekDeck(_session->snapshot().engine.master, seconds);
    [self publishSnapshotIfChanged];
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
    [self.observers removeAllObjects];
    self.publishedSnapshot = nil;
    if (_session) {
        _session->stopAll();
    }
    _session.reset();
    if (self.engineStarted) {
        [self.audioEngine stop];
        self.engineStarted = NO;
    }
    _engine.reset();
}

@end
