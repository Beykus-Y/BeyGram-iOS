#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// BG Mix (AutoMix) for iOS: a queue of local audio files, prepared in the
// background (decode, BG Beat analysis, BG Mix features) and played through
// AVAudioEngine with smart crossfades. All methods must be called on the main
// thread.
@interface BGMixPlayer : NSObject

// cacheDirectory: app-private folder for analysis (.bgm) and feature (.bgf) caches.
- (instancetype)initWithCacheDirectory:(NSString *)cacheDirectory;

// Adds a local file URL to the queue. Returns a non-zero track identifier, or 0 when rejected.
- (uint64_t)addTrackAtURL:(NSURL *)url;
- (void)removeTrackWithIdentifier:(uint64_t)identifier;
- (void)clearQueue;

- (void)play;
- (void)pause;
// Starts a smooth crossfade to the next prepared track.
- (void)next;
- (void)stopAll;
- (BOOL)isTransitionActive;

- (void)setTransitionDuration:(double)seconds; // 0 = automatic
- (void)setAdaptiveTransitions:(BOOL)enabled;
- (void)setBassSwap:(BOOL)enabled;

// Stops the audio engine and the UI update loop. Call before releasing the player.
- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
