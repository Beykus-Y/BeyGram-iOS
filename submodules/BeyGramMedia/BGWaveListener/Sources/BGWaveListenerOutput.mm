#import "BGWaveListener/BGWaveListenerOutput.h"

#import <AVFoundation/AVFoundation.h>

#include <stdlib.h>

// The BG Wave wire format (kWaveSampleRate and kWaveChannels in BG-Media). The engine resamples to the hardware rate.
static const double kListenerSampleRate = 48000.0;
static const AVAudioChannelCount kListenerChannels = 2;
// The largest slice rendered from the scratch buffer. A longer request is filled with silence after this many frames.
static const NSUInteger kListenerMaxFrames = 4096;

// Runs on the real-time audio thread. It takes no self and allocates nothing: `scratch` is allocated in init.
static OSStatus BGWaveListenerRender(BGWaveListenerPullBlock pull,
                                     float *scratch,
                                     BOOL *isSilence,
                                     AVAudioFrameCount frameCount,
                                     AudioBufferList *outputData) {
    if (isSilence != NULL) {
        *isSilence = YES;
    }
    if (outputData->mNumberBuffers < 2) {
        return noErr;
    }
    float *left = (float *)outputData->mBuffers[0].mData;
    float *right = (float *)outputData->mBuffers[1].mData;
    if (left == NULL || right == NULL) {
        return noErr;
    }
    const NSUInteger frames = frameCount;
    const NSUInteger want = frames < kListenerMaxFrames ? frames : kListenerMaxFrames;
    NSUInteger got = 0;
    if (pull != nil && scratch != NULL) {
        got = pull(scratch, want, (uint32_t)kListenerSampleRate);
        if (got > want) {
            got = want;
        }
    }
    for (NSUInteger i = 0; i < got; i++) {
        left[i] = scratch[2 * i];
        right[i] = scratch[2 * i + 1];
    }
    for (NSUInteger i = got; i < frames; i++) {
        left[i] = 0.0f;
        right[i] = 0.0f;
    }
    if (isSilence != NULL) {
        *isSilence = (got == 0);
    }
    return noErr;
}

@interface BGWaveListenerOutput () {
    // Allocated once, in init. The render function reads it and never allocates.
    float *_scratch;
}

@property (nonatomic, copy) BGWaveListenerPullBlock pullBlock;
@property (nonatomic, strong, nullable) AVAudioEngine *engine;
@property (nonatomic, strong, nullable) AVAudioSourceNode *sourceNode;
@property (nonatomic, strong) NSMutableArray<id<NSObject>> *observers;
@property (nonatomic, readwrite) BOOL isRunning;
// Set by start and cleared by stop. An interruption or a route change restarts the engine only while it is set.
@property (nonatomic) BOOL shouldRun;

@end

@implementation BGWaveListenerOutput

- (instancetype)initWithPullBlock:(BGWaveListenerPullBlock)pullBlock {
    self = [super init];
    if (self != nil) {
        _pullBlock = [pullBlock copy];
        _managesAudioSession = YES;
        _observers = [NSMutableArray array];
        _scratch = (float *)calloc((size_t)kListenerMaxFrames * (size_t)kListenerChannels, sizeof(float));
    }
    return self;
}

- (void)dealloc {
    [self stop];
    free(_scratch);
    _scratch = NULL;
}

- (BOOL)startWithError:(NSError **)error {
    if (self.isRunning) {
        return YES;
    }
    self.shouldRun = YES;
    if (![self activateSessionWithError:error] || ![self startEngineWithError:error]) {
        self.shouldRun = NO;
        return NO;
    }
    [self observeNotifications];
    return YES;
}

- (void)stop {
    self.shouldRun = NO;
    [self removeObservers];
    [self.engine stop];
    self.isRunning = NO;
}

#pragma mark - Engine

- (BOOL)activateSessionWithError:(NSError **)error {
    if (!self.managesAudioSession) {
        return YES;
    }
    AVAudioSession *session = [AVAudioSession sharedInstance];
    return [session setCategory:AVAudioSessionCategoryPlayback
                           mode:AVAudioSessionModeDefault
                        options:0
                          error:error]
        && [session setActive:YES error:error];
}

- (BOOL)startEngineWithError:(NSError **)error {
    if (self.engine == nil) {
        AVAudioFormat *format = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                                                 sampleRate:kListenerSampleRate
                                                                   channels:kListenerChannels
                                                                interleaved:NO];
        if (format == nil) {
            return NO;
        }
        // The render block keeps its own copies of the pull block and the scratch pointer. It does not capture self.
        BGWaveListenerPullBlock pull = self.pullBlock;
        float *scratch = _scratch;
        AVAudioSourceNode *node = [[AVAudioSourceNode alloc] initWithFormat:format
                                                                renderBlock:^OSStatus(BOOL *isSilence,
                                                                                      const AudioTimeStamp *timestamp,
                                                                                      AVAudioFrameCount frameCount,
                                                                                      AudioBufferList *outputData) {
            return BGWaveListenerRender(pull, scratch, isSilence, frameCount, outputData);
        }];
        AVAudioEngine *engine = [[AVAudioEngine alloc] init];
        [engine attachNode:node];
        [engine connect:node to:engine.mainMixerNode format:format];
        self.sourceNode = node;
        self.engine = engine;
    }
    [self.engine prepare];
    if (![self.engine startAndReturnError:error]) {
        return NO;
    }
    self.isRunning = YES;
    return YES;
}

#pragma mark - Notifications

- (void)observeNotifications {
    if (self.observers.count > 0) {
        return;
    }
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    __weak BGWaveListenerOutput *weakSelf = self;
    [self.observers addObject:[center addObserverForName:AVAudioEngineConfigurationChangeNotification
                                                  object:nil
                                                   queue:nil
                                              usingBlock:^(NSNotification *note) {
        [weakSelf handleConfigurationChange];
    }]];
    [self.observers addObject:[center addObserverForName:AVAudioSessionInterruptionNotification
                                                  object:nil
                                                   queue:nil
                                              usingBlock:^(NSNotification *note) {
        [weakSelf handleInterruption:note];
    }]];
}

- (void)removeObservers {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    for (id token in self.observers) {
        [center removeObserver:token];
    }
    [self.observers removeAllObjects];
}

// The hardware route changed (headphones, Bluetooth). The engine has stopped and needs a new start.
- (void)handleConfigurationChange {
    if (!self.shouldRun) {
        return;
    }
    if (![self startEngineWithError:NULL]) {
        self.isRunning = NO;
    }
}

- (void)handleInterruption:(NSNotification *)note {
    NSNumber *typeValue = note.userInfo[AVAudioSessionInterruptionTypeKey];
    if (typeValue == nil) {
        return;
    }
    if ((AVAudioSessionInterruptionType)typeValue.unsignedIntegerValue == AVAudioSessionInterruptionTypeBegan) {
        [self.engine pause];
        self.isRunning = NO;
        return;
    }
    if (!self.shouldRun) {
        return;
    }
    if (self.managesAudioSession) {
        [[AVAudioSession sharedInstance] setActive:YES error:NULL];
    }
    if (![self startEngineWithError:NULL]) {
        self.isRunning = NO;
    }
}

@end
