// BG Wave listener session for iOS (stage 4 in docs/bg-wave-ios.md). It joins a session from an invite link and plays the
// listener stream through BGWaveListenerOutput. It exposes what the BG Wave screen needs: the invite exchange, start and
// stop, and the failure kind. The screen and the invite card are UI, not this class.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BGWaveListenerFailure) {
    BGWaveListenerFailureNone = 0,
    // The P2P attempt ended without a selected candidate pair. iOS reports a denied Local Network permission to no API,
    // so this is a suspicion. Show the hint with "possibly", never as a fact.
    BGWaveListenerFailureLocalNetworkSuspected,
    BGWaveListenerFailureOther,
};

extern NSErrorDomain const BGWaveListenerSessionErrorDomain;

@interface BGWaveListenerSession : NSObject

- (instancetype)init NS_DESIGNATED_INITIALIZER;

// Joins from an invite link, in either form (bg://wave/v1/ or the https wrapper). Returns NO and fills `error` with code 1
// when the link is invalid or longer than 4096 characters. The error carries no link text.
- (BOOL)acceptInviteLink:(NSString *)link
          nowUnixSeconds:(int64_t)nowUnixSeconds
                   error:(NSError * _Nullable * _Nullable)error;

// The next invite to send, in the https form that Telegram accepts, or nil when none is queued.
- (nullable NSString *)pollOutboundInvite;

// Starts the audio output and the pipeline timer. Returns NO and fills `error` when the output cannot start.
- (BOOL)startListeningWithError:(NSError * _Nullable * _Nullable)error;

// Ends the session and queues the End invite for pollOutboundInvite. Safe to call more than once.
- (void)stop;

// The failure of the current session, or BGWaveListenerFailureNone.
@property (nonatomic, readonly) BGWaveListenerFailure failure;

@end

NS_ASSUME_NONNULL_END
