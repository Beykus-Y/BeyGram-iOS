#import "BeyGramMedia/BGMixPlayer.h"

#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

#include <cstring>
#include <filesystem>
#include <functional>
#include <memory>
#include <string>
#include <string_view>

#include "bgmedia/audio/AudioData.hpp"
#include "bgmedia/mix/MixEngine.hpp"
#include "bgmedia/mix/MixSession.hpp"
#include "BGMediaMixPreparation.hpp"

namespace {

constexpr uint32_t kSampleRate = 48000;
constexpr AVAudioFrameCount kScratchFrames = 4096;

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

} // namespace

@interface BGMixPlayer () {
    // Declaration order matters: the session must be destroyed before the engine.
    std::unique_ptr<bgmedia::mix::MixEngine> _engine;
    std::unique_ptr<bgmedia::mix::MixSession> _session;
    float *_scratch;
}
@property (nonatomic, strong) AVAudioEngine *audioEngine;
@property (nonatomic, strong) AVAudioSourceNode *sourceNode;
@property (nonatomic, strong, nullable) CADisplayLink *displayLink;
@property (nonatomic) BOOL engineStarted;
@end

@implementation BGMixPlayer

- (instancetype)initWithCacheDirectory:(NSString *)cacheDirectory {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _scratch = (float *)calloc((size_t)kScratchFrames * 2, sizeof(float));
    _engine = std::make_unique<bgmedia::mix::MixEngine>(kSampleRate);

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
    if (_session) {
        _session->update();
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

- (uint64_t)addTrackAtURL:(NSURL *)url {
    if (!url.isFileURL || url.path == nil || !_session) {
        return 0;
    }
    return _session->addTrack(std::filesystem::path(url.path.UTF8String));
}

- (void)removeTrackWithIdentifier:(uint64_t)identifier {
    if (_session) {
        _session->removeTrack(identifier);
    }
}

- (void)clearQueue {
    if (_session) {
        _session->clearQueue();
    }
}

- (void)play {
    [self ensureEngineRunning];
    if (_session) {
        _session->play();
    }
}

- (void)pause {
    if (_session) {
        _session->pause();
    }
}

- (void)next {
    [self ensureEngineRunning];
    if (_session) {
        _session->next();
    }
}

- (void)stopAll {
    if (_session) {
        _session->stopAll();
    }
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
    [self.displayLink invalidate];
    self.displayLink = nil;
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
