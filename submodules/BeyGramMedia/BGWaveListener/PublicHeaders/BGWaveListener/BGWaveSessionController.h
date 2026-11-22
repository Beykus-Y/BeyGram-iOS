// BG Wave session facade for iOS: the Objective-C entry point for the BG Wave screen, the invitation card and the chat
// glue. It hosts or joins one wave at a time through BGWaveController, the portable port of Android's BgWaveController,
// over BGWaveRuntime (Opus, libdatachannel and BGWaveSession). It has no UIKit. The screen, the card and the Telegram
// send path are UI and stay outside this class. The contract for them is docs/bg-wave-ui-contract.md.
//
// Threading: call every method from any thread. Each call runs asynchronously on one private serial queue, which owns
// the controller and the native session. Completions, the delegate, outboundLinkHandler and hostTapHandler run on the
// main queue. The one wait on the main queue is the detach of the host tap (hostTapHandler(NULL)), which runs
// synchronously just before the native session is released. So a caller on the main queue must never wait on the facade.
//
// Lifecycle: call -invalidate once before the last reference goes. It runs asynchronously and stops the timers and the
// listener audio, and it detaches the host tap before the native session is released.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// The values and their order follow the C++ controller, Android's BgWavePhase and BgWaveErrors.
typedef NS_ENUM(NSInteger, BGWaveSessionRole) {
    BGWaveSessionRoleHost = 0,
    BGWaveSessionRoleListener,
};

typedef NS_ENUM(NSInteger, BGWaveSessionPhase) {
    BGWaveSessionPhaseOffering = 0,
    BGWaveSessionPhaseAwaitingAnswer,
    BGWaveSessionPhaseConnecting,
    BGWaveSessionPhaseLive,
    BGWaveSessionPhaseReconnecting,
    BGWaveSessionPhaseFailed,
    BGWaveSessionPhaseEnded,
};

typedef NS_ENUM(NSInteger, BGWaveSessionError) {
    BGWaveSessionErrorNone = 0,
    BGWaveSessionErrorUnavailable,
    BGWaveSessionErrorSendFailed,
    BGWaveSessionErrorNoConnection,
    BGWaveSessionErrorBusy,
    BGWaveSessionErrorExpired,
    BGWaveSessionErrorRejected,
    BGWaveSessionErrorOfferTooLarge,
};

typedef NS_ENUM(NSInteger, BGWaveSessionRoute) {
    BGWaveSessionRouteNone = 0,
    BGWaveSessionRouteDirect,
    BGWaveSessionRouteExternalCall,
};

typedef NS_ENUM(NSInteger, BGWaveInviteStatus) {
    BGWaveInviteStatusPending = 0,
    BGWaveInviteStatusJoined,
    BGWaveInviteStatusDeclined,
    BGWaveInviteStatusCancelled,
    BGWaveInviteStatusEnded,
    BGWaveInviteStatusExpired,
};

// The localisation key the UI shows for an error, such as "bgwave_error_busy" (BeyGramL10n). nil for None.
FOUNDATION_EXPORT NSString * _Nullable BGWaveSessionErrorLocalizationKey(BGWaveSessionError error);

// The wave the user sees. Everything shown is derived from this object.
@interface BGWaveSessionModel : NSObject

@property (nonatomic, readonly) BGWaveSessionRole role;
@property (nonatomic, readonly, copy) NSString *accountId;
@property (nonatomic, readonly) int64_t chatId;
@property (nonatomic, readonly) int64_t peerId;
// Empty until the offer exists (host), or while only the invitation is known (listener).
@property (nonatomic, readonly, copy) NSString *sidHex;
@property (nonatomic, readonly) BGWaveSessionPhase phase;
// Set only in the failed phase, and for refusals that keep the current wave.
@property (nonatomic, readonly) BGWaveSessionError error;
// A status only, never a promise.
@property (nonatomic, readonly) BGWaveSessionRoute route;
// Host only: the playing source cannot be sent into the wave, so the listener hears nothing.
@property (nonatomic, readonly) BOOL sourceUnsupported;
// A suspicion, never a fact: the P2P attempt failed without a selected candidate pair, which a denied Local Network
// permission can cause. Show it with "possibly". Set only in the failed phase.
@property (nonatomic, readonly) BOOL localNetworkHint;

- (instancetype)initWithRole:(BGWaveSessionRole)role
                   accountId:(NSString *)accountId
                      chatId:(int64_t)chatId
                      peerId:(int64_t)peerId
                      sidHex:(NSString *)sidHex
                       phase:(BGWaveSessionPhase)phase
                       error:(BGWaveSessionError)error
                       route:(BGWaveSessionRoute)route
           sourceUnsupported:(BOOL)sourceUnsupported
            localNetworkHint:(BOOL)localNetworkHint NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

// One received invitation, as the card of its message shows it.
@interface BGWaveInviteModel : NSObject

@property (nonatomic, readonly, copy) NSString *sidHex;
@property (nonatomic, readonly, copy) NSString *accountId;
@property (nonatomic, readonly) int64_t chatId;
@property (nonatomic, readonly) int64_t senderId;
// The link as received, in either form.
@property (nonatomic, readonly, copy) NSString *uri;
@property (nonatomic, readonly) int64_t expiresAt;
@property (nonatomic, readonly) BGWaveInviteStatus status;

- (instancetype)initWithSidHex:(NSString *)sidHex
                     accountId:(NSString *)accountId
                        chatId:(int64_t)chatId
                      senderId:(int64_t)senderId
                           uri:(NSString *)uri
                     expiresAt:(int64_t)expiresAt
                        status:(BGWaveInviteStatus)status NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

// Everything the UI shows, read in one piece. Invitations are in arrival order.
@interface BGWaveSnapshotModel : NSObject

@property (nonatomic, readonly, nullable) BGWaveSessionModel *session;
@property (nonatomic, readonly, copy) NSArray<BGWaveInviteModel *> *invites;

- (instancetype)initWithSession:(nullable BGWaveSessionModel *)session
                        invites:(NSArray<BGWaveInviteModel *> *)invites NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

// A call that produces a link. The https link to send, the session it belongs to, and the failure when there is no link.
// The failure is None when the call was refused without any change, for example for an invitation that is no longer
// pending.
typedef void (^BGWaveSessionLinkCompletion)(NSString * _Nullable https,
                                            NSString * _Nullable sidHex,
                                            BGWaveSessionError error);

@class BGWaveSessionController;

@protocol BGWaveSessionControllerDelegate <NSObject>

// Called on the main queue after every change of the wave or of the invitations.
- (void)waveSessionController:(BGWaveSessionController *)controller didChangeSnapshot:(BGWaveSnapshotModel *)snapshot;

@end

@interface BGWaveSessionController : NSObject

@property (nonatomic, weak, nullable) id<BGWaveSessionControllerDelegate> delegate;

// Main queue. A link the session produced on its own, from a poll, to send in the chat of the wave (session.chatId).
@property (nonatomic, copy, nullable) void (^outboundLinkHandler)(NSString *https);

// Main queue. The host tap of the session, a bgmedia::IPcmOutputTap * passed as void *, when a host session starts. It
// is NULL just before the session is released. Attach it to the mix player with setPcmTap:, and detach it on NULL.
@property (nonatomic, copy, nullable) void (^hostTapHandler)(void * _Nullable tap);

- (instancetype)init NS_DESIGNATED_INITIALIZER;

// Reads the snapshot. The completion runs on the main queue.
- (void)snapshotWithCompletion:(void (^)(BGWaveSnapshotModel *snapshot))completion;

// Host: starts a wave with peerId in the private chat chatId. The completion gives the https offer to send.
- (void)startHostingForAccountId:(NSString *)accountId
                          chatId:(int64_t)chatId
                          peerId:(int64_t)peerId
                      completion:(BGWaveSessionLinkCompletion)completion;

// Host: the offer was handed to Telegram (success) or was not. A failed send tears the wave down.
- (void)offerSentForSidHex:(NSString *)sidHex success:(BOOL)success;

// Host: whether the playing source can be sent into the wave. Unchanged values change nothing.
- (void)setHostSourceUnsupported:(BOOL)unsupported forSidHex:(NSString *)sidHex;

// One Telegram message that may carry a wave link. link is the hidden link of the message, or nil for none. Outgoing
// messages never drive a wave. privateChat must be YES only for an ordinary one-to-one chat (not a group, a channel or
// a secret chat).
- (void)receiveLink:(nullable NSString *)link
          accountId:(NSString *)accountId
             chatId:(int64_t)chatId
           senderId:(int64_t)senderId
           outgoing:(BOOL)outgoing
        privateChat:(BOOL)privateChat
          messageId:(int64_t)messageId;

// Listener: joins a pending invitation. The completion gives the https answer to send.
- (void)joinSidHex:(NSString *)sidHex completion:(BGWaveSessionLinkCompletion)completion;

// Listener: the answer could not be handed to Telegram, so the wave cannot start.
- (void)answerSendFailedForSidHex:(NSString *)sidHex;

// Listener: declines a pending invitation. The completion gives the https Cancel for the host.
- (void)declineSidHex:(NSString *)sidHex completion:(void (^)(NSString * _Nullable https))completion;

// Either role: stops the wave. The completion gives the https Cancel (before an answer) or End for the peer, or nil.
- (void)stopWithCompletion:(void (^)(NSString * _Nullable https))completion;

// Retry after a failure. The completion says whether a reconnect started.
- (void)retryWithCompletion:(void (^)(BOOL started))completion;

// Clears a finished or failed wave from the screen.
- (void)dismiss;

// A Cancel for an offer whose send finished after stop() had already ended the local wave. The completion gives it.
- (void)cancelLinkForSidHex:(NSString *)sidHex completion:(void (^)(NSString * _Nullable https))completion;

// Clears one account's invitations. The wave is closed only when it belongs to that account.
- (void)resetAccountId:(NSString *)accountId;

// The offer of a session is a Telegram message, so that deleting or editing that message can retire the offer.
- (void)noteOfferMessageForAccountId:(NSString *)accountId
                              chatId:(int64_t)chatId
                           messageId:(int64_t)messageId
                              sidHex:(NSString *)sidHex;

// The offer message was deleted or edited. stillValidSidHex is the session it carries now, or nil for none.
- (void)offerMessageGoneForAccountId:(NSString *)accountId
                              chatId:(int64_t)chatId
                           messageId:(int64_t)messageId
                    stillValidSidHex:(nullable NSString *)stillValidSidHex;

// Releases the wave and the native session. Call once, before the last reference goes.
- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
