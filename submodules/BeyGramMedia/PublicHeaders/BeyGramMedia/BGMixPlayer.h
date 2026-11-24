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

// Posted on the main thread when a BGMixPlayer that manages its own AVAudioSession starts playback,
// so Telegram's native MediaPlayer can pause cleanly without conflicting audio output.
extern NSNotificationName const BGMixPlayerDidStartPlaybackNotification;

// Posted on the main thread when the shared BGMixPlayer is stopped because Telegram's native
// MediaPlayer is taking over audio playback, so BG Mix releases system Now Playing controls cleanly.
extern NSNotificationName const BGMixPlayerDidStopForExternalAudioNotification;

// BG Mix (AutoMix) for iOS: a queue of local audio files, prepared in the background (decode,
// BG Beat analysis, BG Mix features) and played through AVAudioEngine with smart crossfades.
// All methods and all observer callbacks run on the main thread. The contract is in
// docs/bg-mix-player-api.md.
@interface BGMixPlayer : NSObject

// The app's player. It belongs to the app, not to the BG Mix screen, so closing the screen does not stop
// the mix. Created on first use.
+ (BGMixPlayer *)sharedPlayer;

// If the shared player already exists and is currently playing, pauses and stops its audio engine.
// Never instantiates the shared player if it has not been created yet.
+ (void)stopSharedEngineIfRunning;

// Documents/bgmix: the queued copies and the analysis caches. Created on first use.
+ (NSURL *)mixDirectory;

// cacheDirectory: app-private folder for analysis (.bgm) and feature (.bgf) caches.
- (instancetype)initWithCacheDirectory:(NSString *)cacheDirectory;

// Queue. addTrackAtURL: returns a non-zero track identifier, or 0 when the file is rejected.
- (uint64_t)addTrackAtURL:(NSURL *)url NS_SWIFT_NAME(addTrack(at:));
// Atomically stops playback, drains and clears both decks, adds `url`, and starts playback.
// Prevents "busy deck" races when replacing the queue while audio is playing.
- (uint64_t)replaceQueueAndPlayTrackAtURL:(NSURL *)url NS_SWIFT_NAME(replaceQueueAndPlayTrack(at:));
// Returns NO when no track has this identifier.
- (BOOL)removeTrackWithIdentifier:(uint64_t)identifier NS_SWIFT_NAME(removeTrack(withIdentifier:));
- (void)clearQueue;

// Transport.
- (void)play;
- (void)pause;
// Starts a smooth crossfade to the next prepared track.
- (void)next;
// Attempts to start a crossfade to the next prepared track. Returns YES only if the engine
// actually entered an active transition; returns NO if the next track is not ready or the
// transition plan was rejected.
- (BOOL)tryStartNextTransition;
- (void)stopAll;
// Moves the master deck to `seconds`. Returns NO during a transition, when nothing is loaded, or
// for a negative or non-finite value.
- (BOOL)seekToPosition:(NSTimeInterval)seconds NS_SWIFT_NAME(seek(toPosition:));
- (BOOL)isTransitionActive;

- (void)setTransitionDuration:(double)seconds; // 0 = automatic
- (void)setAdaptiveTransitions:(BOOL)enabled;
- (void)setBassSwap:(BOOL)enabled;

/// Equalizer for the BG Mix output (issue #139). Off by default: with it off the graph is the one that was always built.
/// `gainsDecibels` has one value per band (5 bands, each clamped to -12...12 dB). It takes effect when the engine is next built, not
/// while playing. NOT CHECKED ON A DEVICE: this changes the audio graph, so it is opt-in.
- (void)setEqualizerEnabled:(BOOL)enabled gainsDecibels:(NSArray<NSNumber *> *)gainsDecibels;

// The current state, read from the engine on each access.
@property (nonatomic, readonly) BGMixSnapshot *snapshot;

// Observers are held weakly. A new observer gets the current snapshot at once, then later changes.
- (void)addObserver:(id<BGMixPlayerObserver>)observer;
- (void)removeObserver:(id<BGMixPlayerObserver>)observer;

// Who configures and activates AVAudioSession. YES (the default) lets the player do it itself, which is what
// the BG Mix screen needs. The app's music path sets NO: its session manager activates the session before play,
// and the player only starts and stops its engine. Such a player does not resume by itself after an
// interruption. The music path sets YES again when it lets go.
@property (nonatomic) BOOL managesAudioSession;

// Pauses, then stops the audio engine at once. The session manager calls it when it takes the session away.
- (void)stopEngine;

// Host tap for BG Wave. `tap` is a `bgmedia::IPcmOutputTap *`, passed as an opaque pointer so that this
// header stays plain Objective-C. The realtime render thread calls its onPcmRendered after each rendered
// chunk (up to 4096 frames): interleaved stereo float at 48 kHz, no allocation. Pass NULL to detach. The
// call returns only after the render thread has left any call into the previous tap, so the owner may
// destroy that tap afterwards. Main thread only.
- (void)setPcmTap:(nullable void *)tap;

// Stops the audio engine and the update loop, detaches the host tap, and drops the observers. Call before
// releasing the player. The shared player is not invalidated in normal use.
- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
