// BG Wave listener output (stage 2 in docs/bg-wave-ios.md). AVAudioEngine plays the stereo stream that a session decodes.
// This class knows nothing about the session: the caller passes a pull block.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Fills `outInterleavedStereo` with up to `frames` stereo float frames at `sampleRate`, and returns how many it wrote.
// It runs on the real-time audio thread, so it must not lock, allocate or capture self.
// BGWaveSession::pullListenerPcm meets this rule.
typedef NSUInteger (^BGWaveListenerPullBlock)(float *outInterleavedStereo, NSUInteger frames, uint32_t sampleRate);

@interface BGWaveListenerOutput : NSObject

- (instancetype)initWithPullBlock:(BGWaveListenerPullBlock)pullBlock NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// YES by default: starting sets the shared AVAudioSession to playback and activates it. Set NO when another part of
// the app owns the session (BG Mix does).
@property (nonatomic) BOOL managesAudioSession;

@property (nonatomic, readonly) BOOL isRunning;

// Starts AVAudioEngine. Returns NO and fills `error` when the session or the engine cannot start.
- (BOOL)startWithError:(NSError * _Nullable * _Nullable)error;

// Stops the engine. The audio session stays active, because BG Mix may still be playing.
- (void)stop;

@end

NS_ASSUME_NONNULL_END
