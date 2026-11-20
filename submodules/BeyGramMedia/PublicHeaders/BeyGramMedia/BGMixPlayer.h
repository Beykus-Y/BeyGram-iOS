#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class BGMixPlayer;

// Where one queued track is: waiting, being prepared, ready, playing on a deck, finished or failed.
typedef NS_ENUM(NSInteger, BGMixTrackState) {
    BGMixTrackStatePending = 0,
    BGMixTrackStatePreparing,
    BGMixTrackStateReady,
    BGMixTrackStatePlaying,
    BGMixTrackStatePlayed,
    BGMixTrackStateFailed,
};

// What the player does. Paused means a track is loaded but silent.
typedef NS_ENUM(NSInteger, BGMixTransport) {
    BGMixTransportStopped = 0,
    BGMixTransportPlaying,
    BGMixTransportPaused,
};

// One queue entry. Immutable: take a new snapshot to see changes.
@interface BGMixTrack : NSObject
@property (nonatomic, readonly) uint64_t identifier;
@property (nonatomic, readonly, copy) NSString *name;
// The app-private copy the player decodes from.
@property (nonatomic, readonly, copy) NSURL *fileURL;
@property (nonatomic, readonly) BGMixTrackState state;
// 0...1 while preparing, 1 once ready.
@property (nonatomic, readonly) float progress;
// Seconds. 0 until the track is prepared.
@property (nonatomic, readonly) NSTimeInterval duration;
// Analysed tempo in BPM. 0 until known.
@property (nonatomic, readonly) double bpm;
@property (nonatomic, readonly, nullable, copy) NSString *error;
@end

// The player's state at one moment. Immutable.
@interface BGMixSnapshot : NSObject
@property (nonatomic, readonly) BGMixTransport transport;
// The track on the master deck, or nil when that deck is empty.
@property (nonatomic, readonly, nullable) BGMixTrack *currentTrack;
// Seconds into currentTrack.
@property (nonatomic, readonly) NSTimeInterval position;
// Length of currentTrack in seconds.
@property (nonatomic, readonly) NSTimeInterval duration;
// The track on the other deck. It takes over at the next transition. nil when that deck is empty.
@property (nonatomic, readonly, nullable) BGMixTrack *nextTrack;
@property (nonatomic, readonly) BOOL transitionActive;
// 0...1 through the running transition.
@property (nonatomic, readonly) float transitionProgress;
@property (nonatomic, readonly) BOOL preparingNext;
// The queue in the order the tracks were added.
@property (nonatomic, readonly, copy) NSArray<BGMixTrack *> *queue;
// The engine's last error, or the system's last refusal to start audio, or nil.
@property (nonatomic, readonly, nullable, copy) NSString *lastError;
@end

// Receives snapshots on the main thread. See -addObserver: on BGMixPlayer.
@protocol BGMixPlayerObserver <NSObject>
- (void)mixPlayer:(BGMixPlayer *)player didUpdateSnapshot:(BGMixSnapshot *)snapshot;
@end

// BG Mix (AutoMix) for iOS: a queue of local audio files, prepared in the background (decode,
// BG Beat analysis, BG Mix features) and played through AVAudioEngine with smart crossfades.
// All methods and all observer callbacks run on the main thread. The contract is in
// docs/bg-mix-player-api.md.
@interface BGMixPlayer : NSObject

// The app's player. It belongs to the app, not to the BG Mix screen, so closing the screen does not stop
// the mix. Created on first use.
+ (BGMixPlayer *)sharedPlayer;

// Documents/bgmix: the queued copies and the analysis caches. Created on first use.
+ (NSURL *)mixDirectory;

// cacheDirectory: app-private folder for analysis (.bgm) and feature (.bgf) caches.
- (instancetype)initWithCacheDirectory:(NSString *)cacheDirectory;

// Queue. addTrackAtURL: returns a non-zero track identifier, or 0 when the file is rejected.
- (uint64_t)addTrackAtURL:(NSURL *)url;
// Returns NO when no track has this identifier.
- (BOOL)removeTrackWithIdentifier:(uint64_t)identifier;
- (void)clearQueue;

// Transport.
- (void)play;
- (void)pause;
// Starts a smooth crossfade to the next prepared track.
- (void)next;
- (void)stopAll;
// Moves the master deck to `seconds`. Returns NO during a transition, when nothing is loaded, or
// for a negative or non-finite value.
- (BOOL)seekToPosition:(NSTimeInterval)seconds;
- (BOOL)isTransitionActive;

- (void)setTransitionDuration:(double)seconds; // 0 = automatic
- (void)setAdaptiveTransitions:(BOOL)enabled;
- (void)setBassSwap:(BOOL)enabled;

// The current state, read from the engine on each access.
@property (nonatomic, readonly) BGMixSnapshot *snapshot;

// Observers are held weakly. A new observer gets the current snapshot at once, then later changes.
- (void)addObserver:(id<BGMixPlayerObserver>)observer;
- (void)removeObserver:(id<BGMixPlayerObserver>)observer;

// Stops the audio engine and the update loop, and drops the observers. Call before releasing the player.
// The shared player is not invalidated in normal use.
- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
