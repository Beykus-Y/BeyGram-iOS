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

// Decodes any file AVFoundation can read (MP3, AAC/M4A, FLAC, WAV, ALAC) into
// interleaved float PCM. Runs on the MixSession worker thread.
bool decodeWithAVFoundation(const std::filesystem::path &path,
                            bgmedia::AudioData &out, std::string &error) {
    @autoreleasepool {
        NSString *filePath = [NSString stringWithUTF8String:path.c_str()];
        if (filePath == nil) {
            error = "Invalid file path.";
            return false;
        }
        NSError *nsError = nil;
        AVAudioFile *file = [[AVAudioFile alloc] initForReading:[NSURL fileURLWithPath:filePath] error:&nsError];
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
        AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format
                                                                 frameCapacity:(AVAudioFrameCount)length];
        if (buffer == nil || ![file readIntoBuffer:buffer error:&nsError]) {
            error = nsError.localizedDescription.UTF8String ?: "Could not decode audio file.";
            return false;
        }
        const uint32_t channels = (uint32_t)format.channelCount;
        const size_t frames = (size_t)buffer.frameLength;
        out.channels = channels;
        out.sampleRate = (uint32_t)format.sampleRate;
        out.samples.assign(frames * channels, 0.0f);
        for (uint32_t ch = 0; ch < channels; ++ch) {
            const float *src = buffer.floatChannelData[ch];
            for (size_t i = 0; i < frames; ++i) {
                out.samples[i * channels + ch] = src[i];
            }
        }
        return out.valid();
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
    _session = std::make_unique<bgmedia::mix::MixSession>(
        *_engine,
        [options](const std::filesystem::path &path, bgmedia::mix::PreparedMixTrack &out,
                  std::string &error, std::function<void(float, std::string_view)> progress) {
            return beygram::media::prepareMixTrack(path, decodeWithAVFoundation, options, out, error, progress);
        });

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
