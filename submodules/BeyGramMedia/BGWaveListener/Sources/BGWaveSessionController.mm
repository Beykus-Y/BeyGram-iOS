#import "BGWaveListener/BGWaveSessionController.h"

#import "BGWaveListener/BGWaveListenerOutput.h"

#import <Network/Network.h>

#include "BGWaveRuntime.hpp"

#include "../../BGWaveCore/BGWaveController.hpp"

#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

// BGWaveController::pump wants about 10 ms, as Android's pump does. The timer runs off the audio thread.
static const uint64_t kPumpIntervalNs = 10 * NSEC_PER_MSEC;
static const uint64_t kPumpLeewayNs = 1 * NSEC_PER_MSEC;
// poll() runs about once a second: every 100 pump ticks.
static const NSUInteger kPollEveryTicks = 100;

namespace {

class RuntimeNativeSession;

// The native session the facade uses now. The factory creates it and shares this slot, and the session clears the slot
// when it is released. The facade reads the slot only on its queue.
struct NativeSlot {
    RuntimeNativeSession *current = nullptr;
};

// The controller's native session over one BGWaveRuntime. It is the only type that knows both the controller and the
// runtime, so the facade and the controller never see each other's internals.
class RuntimeNativeSession final : public beygram::wave::BGWaveNativeSession {
public:
    RuntimeNativeSession(bool isHost, std::shared_ptr<NativeSlot> slot) : isHost_(isHost), slot_(std::move(slot)) {
        beygram::wave::BGWaveRuntime::Options options;
        options.role = isHost_ ? bgmedia::wave::WaveRole::Host : bgmedia::wave::WaveRole::Listener;
        // The controller passes the same lifetime to startOffer; the runtime keeps it as its own option.
        options.offerTtlSeconds = beygram::wave::kBGWaveOfferTtlSeconds;
        runtime_ = std::make_unique<beygram::wave::BGWaveRuntime>(options);
        slot_->current = this;
    }

    ~RuntimeNativeSession() override {
        if (slot_->current == this) {
            slot_->current = nullptr;
        }
    }

    bool startOffer(std::int64_t nowUnixSeconds, std::int64_t offerTtlSeconds) override {
        if (!isHost_ || offerTtlSeconds != beygram::wave::kBGWaveOfferTtlSeconds) {
            return false;
        }
        return runtime_->startOffer(nowUnixSeconds);
    }

    bool handleRemote(std::string_view link, std::int64_t nowUnixSeconds) override {
        return runtime_->acceptInvite(link, nowUnixSeconds, nullptr);
    }

    std::optional<std::string> pollOutbound() override {
        return runtime_->pollOutboundInvite();
    }

    beygram::wave::BGWaveNativeStatus status() const override {
        beygram::wave::BGWaveNativeStatus result;
        result.state = runtime_->state();
        result.route = runtime_->route();
        result.lastError = runtime_->lastError();
        return result;
    }

    void stop(bool emitEnd, std::int64_t nowUnixSeconds) override {
        runtime_->stop(emitEnd, nowUnixSeconds);
    }

    bool reconnect(std::int64_t nowUnixSeconds) override {
        return runtime_->reconnect(nowUnixSeconds);
    }

    void process(double monotonicSeconds) override {
        runtime_->process(monotonicSeconds);
    }

    bool isHost() const noexcept {
        return isHost_;
    }

    beygram::wave::BGWaveRuntime &runtime() const noexcept {
        return *runtime_;
    }

    beygram::wave::WaveFailureKind failureKind() const {
        return runtime_->failureKind();
    }

    // The host tap, a bgmedia::IPcmOutputTap. It is valid until this session is released.
    void *hostTapPointer() const noexcept {
        return &runtime_->hostTap();
    }

private:
    bool isHost_;
    std::shared_ptr<NativeSlot> slot_;
    std::unique_ptr<beygram::wave::BGWaveRuntime> runtime_;
};

BGWaveSessionRole SessionRoleFrom(beygram::wave::BGWaveRole role) {
    return role == beygram::wave::BGWaveRole::Host ? BGWaveSessionRoleHost : BGWaveSessionRoleListener;
}

BGWaveSessionPhase PhaseFrom(beygram::wave::BGWavePhase phase) {
    switch (phase) {
        case beygram::wave::BGWavePhase::Offering:
            return BGWaveSessionPhaseOffering;
        case beygram::wave::BGWavePhase::AwaitingAnswer:
            return BGWaveSessionPhaseAwaitingAnswer;
        case beygram::wave::BGWavePhase::Connecting:
            return BGWaveSessionPhaseConnecting;
        case beygram::wave::BGWavePhase::Live:
            return BGWaveSessionPhaseLive;
        case beygram::wave::BGWavePhase::Reconnecting:
            return BGWaveSessionPhaseReconnecting;
        case beygram::wave::BGWavePhase::Failed:
            return BGWaveSessionPhaseFailed;
        case beygram::wave::BGWavePhase::Ended:
            return BGWaveSessionPhaseEnded;
    }
    return BGWaveSessionPhaseEnded;
}

beygram::wave::BGWaveError NativeErrorFrom(BGWaveSessionError error) {
    switch (error) {
        case BGWaveSessionErrorNone:
            return beygram::wave::BGWaveError::None;
        case BGWaveSessionErrorUnavailable:
            return beygram::wave::BGWaveError::Unavailable;
        case BGWaveSessionErrorSendFailed:
            return beygram::wave::BGWaveError::SendFailed;
        case BGWaveSessionErrorNoConnection:
            return beygram::wave::BGWaveError::NoConnection;
        case BGWaveSessionErrorBusy:
            return beygram::wave::BGWaveError::Busy;
        case BGWaveSessionErrorExpired:
            return beygram::wave::BGWaveError::Expired;
        case BGWaveSessionErrorRejected:
            return beygram::wave::BGWaveError::Rejected;
        case BGWaveSessionErrorOfferTooLarge:
            return beygram::wave::BGWaveError::OfferTooLarge;
    }
    return beygram::wave::BGWaveError::None;
}

BGWaveSessionError ErrorFrom(beygram::wave::BGWaveError error) {
    switch (error) {
        case beygram::wave::BGWaveError::None:
            return BGWaveSessionErrorNone;
        case beygram::wave::BGWaveError::Unavailable:
            return BGWaveSessionErrorUnavailable;
        case beygram::wave::BGWaveError::SendFailed:
            return BGWaveSessionErrorSendFailed;
        case beygram::wave::BGWaveError::NoConnection:
            return BGWaveSessionErrorNoConnection;
        case beygram::wave::BGWaveError::Busy:
            return BGWaveSessionErrorBusy;
        case beygram::wave::BGWaveError::Expired:
            return BGWaveSessionErrorExpired;
        case beygram::wave::BGWaveError::Rejected:
            return BGWaveSessionErrorRejected;
        case beygram::wave::BGWaveError::OfferTooLarge:
            return BGWaveSessionErrorOfferTooLarge;
    }
    return BGWaveSessionErrorNone;
}

BGWaveSessionRoute RouteFrom(beygram::wave::BGWaveRoute route) {
    switch (route) {
        case beygram::wave::BGWaveRoute::None:
            return BGWaveSessionRouteNone;
        case beygram::wave::BGWaveRoute::Direct:
            return BGWaveSessionRouteDirect;
        case beygram::wave::BGWaveRoute::ExternalCall:
            return BGWaveSessionRouteExternalCall;
    }
    return BGWaveSessionRouteNone;
}

BGWaveInviteStatus InviteStatusFrom(beygram::wave::BGWaveInviteStatus status) {
    switch (status) {
        case beygram::wave::BGWaveInviteStatus::Pending:
            return BGWaveInviteStatusPending;
        case beygram::wave::BGWaveInviteStatus::Joined:
            return BGWaveInviteStatusJoined;
        case beygram::wave::BGWaveInviteStatus::Declined:
            return BGWaveInviteStatusDeclined;
        case beygram::wave::BGWaveInviteStatus::Cancelled:
            return BGWaveInviteStatusCancelled;
        case beygram::wave::BGWaveInviteStatus::Ended:
            return BGWaveInviteStatusEnded;
        case beygram::wave::BGWaveInviteStatus::Expired:
            return BGWaveInviteStatusExpired;
    }
    return BGWaveInviteStatusPending;
}

NSString *StringFrom(const std::string &text) {
    NSString *result = [[NSString alloc] initWithBytes:text.data() length:text.size() encoding:NSUTF8StringEncoding];
    return result != nil ? result : @"";
}

std::string StdStringFrom(NSString *text) {
    const char *utf8 = text.UTF8String;
    return utf8 != NULL ? std::string(utf8) : std::string();
}

int64_t NowUnixSeconds() {
    return static_cast<int64_t>([[NSDate date] timeIntervalSince1970]);
}

}  // namespace

NSString * _Nullable BGWaveSessionErrorLocalizationKey(BGWaveSessionError error) {
    const std::string_view key = beygram::wave::bgWaveErrorKey(NativeErrorFrom(error));
    if (key.empty()) {
        return nil;
    }
    return StringFrom(std::string(key));
}

#pragma mark - Models

@implementation BGWaveSessionModel

- (instancetype)initWithRole:(BGWaveSessionRole)role
                   accountId:(NSString *)accountId
                      chatId:(int64_t)chatId
                      peerId:(int64_t)peerId
                      sidHex:(NSString *)sidHex
                       phase:(BGWaveSessionPhase)phase
                       error:(BGWaveSessionError)error
                       route:(BGWaveSessionRoute)route
           sourceUnsupported:(BOOL)sourceUnsupported
            localNetworkHint:(BOOL)localNetworkHint {
    self = [super init];
    if (self != nil) {
        _role = role;
        _accountId = [accountId copy];
        _chatId = chatId;
        _peerId = peerId;
        _sidHex = [sidHex copy];
        _phase = phase;
        _error = error;
        _route = route;
        _sourceUnsupported = sourceUnsupported;
        _localNetworkHint = localNetworkHint;
    }
    return self;
}

@end

@implementation BGWaveInviteModel

- (instancetype)initWithSidHex:(NSString *)sidHex
                     accountId:(NSString *)accountId
                        chatId:(int64_t)chatId
                      senderId:(int64_t)senderId
                           uri:(NSString *)uri
                     expiresAt:(int64_t)expiresAt
                        status:(BGWaveInviteStatus)status {
    self = [super init];
    if (self != nil) {
        _sidHex = [sidHex copy];
        _accountId = [accountId copy];
        _chatId = chatId;
        _senderId = senderId;
        _uri = [uri copy];
        _expiresAt = expiresAt;
        _status = status;
    }
    return self;
}

@end

@implementation BGWaveSnapshotModel

- (instancetype)initWithSession:(BGWaveSessionModel *)session invites:(NSArray<BGWaveInviteModel *> *)invites {
    self = [super init];
    if (self != nil) {
        _session = session;
        _invites = [invites copy];
    }
    return self;
}

@end

#pragma mark - Controller

@interface BGWaveSessionController () {
    // Owns the controller, and through it the one native session. Every access runs on `queue`.
    std::unique_ptr<beygram::wave::BGWaveController> _controller;
    std::shared_ptr<NativeSlot> _slot;
}

@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong, nullable) dispatch_source_t timer;
@property (nonatomic, strong, nullable) BGWaveListenerOutput *listenerOutput;
// True while the host tap is handed out. The release of the session detaches it first.
@property (nonatomic, assign) BOOL hostTapAttached;
@property (nonatomic, assign) NSUInteger tickCount;
// Watches the network path (issue #143). When it becomes usable again, a failed or reconnecting session asks again.
@property (nonatomic, strong, nullable) nw_path_monitor_t pathMonitor;

- (void)networkPathSatisfied;
- (BGWaveSnapshotModel *)makeSnapshot;
- (void)deliverChange;
- (void)willCloseNativeSession;
- (void)updateTimers;
- (void)startTimer;
- (void)stopTimer;
- (void)tick;
- (void)attachHostTapIfNeeded;
- (void)startListenerOutput;
- (void)stopListenerOutput;
- (NSString *)currentSidHex;
- (BGWaveSessionError)sessionErrorOr:(BGWaveSessionError)fallback;

@end

@implementation BGWaveSessionController

- (void)dealloc {
    if (_pathMonitor != nil) {
        nw_path_monitor_cancel(_pathMonitor);
    }
}

- (void)networkPathSatisfied {
    // Runs on `queue`. The controller only retries from Failed or Reconnecting, so other phases are left alone.
    const bool started = _controller->retry(NowUnixSeconds());
    (void)started;
}

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        _queue = dispatch_queue_create("org.beygram.wave.session", DISPATCH_QUEUE_SERIAL);
        _slot = std::make_shared<NativeSlot>();
        std::shared_ptr<NativeSlot> slot = _slot;
        beygram::wave::BGWaveSessionFactory factory = [slot](bool isHost) {
            return std::unique_ptr<beygram::wave::BGWaveNativeSession>(new RuntimeNativeSession(isHost, slot));
        };
        _controller = std::make_unique<beygram::wave::BGWaveController>(std::move(factory));

        // Network path changes (issue #143). The handler holds the facade weakly and hops to `queue` before touching the controller.
        __weak BGWaveSessionController *weakSelf = self;
        nw_path_monitor_t monitor = nw_path_monitor_create();
        nw_path_monitor_set_queue(monitor, _queue);
        nw_path_monitor_set_update_handler(monitor, ^(nw_path_t path) {
            if (nw_path_get_status(path) != nw_path_status_satisfied) {
                return;
            }
            BGWaveSessionController *strongSelf = weakSelf;
            if (strongSelf != nil) {
                [strongSelf networkPathSatisfied];
            }
        });
        nw_path_monitor_start(monitor);
        _pathMonitor = monitor;

        // These run on `queue`, inside controller calls. They hold the facade unretained, so invalidate must clear them
        // before the facade is released.
        __unsafe_unretained BGWaveSessionController *owner = self;
        _controller->setChangeListener([owner](const beygram::wave::BGWaveSnapshot &) {
            [owner deliverChange];
        });
        _controller->setSessionWillCloseListener([owner]() {
            [owner willCloseNativeSession];
        });
    }
    return self;
}

#pragma mark - Public

- (void)snapshotWithCompletion:(void (^)(BGWaveSnapshotModel *snapshot))completion {
    dispatch_async(self.queue, ^{
        BGWaveSnapshotModel *snapshot = [self makeSnapshot];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion != nil) {
                completion(snapshot);
            }
        });
    });
}

- (void)startHostingForAccountId:(NSString *)accountId
                          chatId:(int64_t)chatId
                          peerId:(int64_t)peerId
                      completion:(BGWaveSessionLinkCompletion)completion {
    const std::string account = StdStringFrom(accountId);
    dispatch_async(self.queue, ^{
        const std::optional<std::string> link =
            _controller->startHosting(account, chatId, peerId, NowUnixSeconds());
        NSString *https = nil;
        NSString *sidHex = nil;
        BGWaveSessionError error = BGWaveSessionErrorNone;
        if (link.has_value()) {
            https = StringFrom(*link);
            sidHex = [self currentSidHex];
            [self attachHostTapIfNeeded];
        } else {
            error = [self sessionErrorOr:BGWaveSessionErrorUnavailable];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion != nil) {
                completion(https, sidHex, error);
            }
        });
    });
}

- (void)offerSentForSidHex:(NSString *)sidHex success:(BOOL)success {
    const std::string sid = StdStringFrom(sidHex);
    dispatch_async(self.queue, ^{
        _controller->offerSent(sid, success ? true : false, NowUnixSeconds());
    });
}

- (void)setHostSourceUnsupported:(BOOL)unsupported forSidHex:(NSString *)sidHex {
    const std::string sid = StdStringFrom(sidHex);
    dispatch_async(self.queue, ^{
        _controller->setHostSourceUnsupported(sid, unsupported ? true : false);
    });
}

- (void)receiveLink:(nullable NSString *)link
          accountId:(NSString *)accountId
             chatId:(int64_t)chatId
           senderId:(int64_t)senderId
           outgoing:(BOOL)outgoing
        privateChat:(BOOL)privateChat
          messageId:(int64_t)messageId {
    if (link == nil) {
        return;
    }
    const std::string uri = StdStringFrom(link);
    const std::string account = StdStringFrom(accountId);
    dispatch_async(self.queue, ^{
        _controller->onMessage(account, chatId, senderId, outgoing ? true : false, privateChat ? true : false, uri,
                               NowUnixSeconds(), messageId);
    });
}

- (void)joinSidHex:(NSString *)sidHex completion:(BGWaveSessionLinkCompletion)completion {
    const std::string sid = StdStringFrom(sidHex);
    dispatch_async(self.queue, ^{
        const std::optional<std::string> link = _controller->join(sid, NowUnixSeconds());
        NSString *https = nil;
        NSString *answerSid = nil;
        BGWaveSessionError error = BGWaveSessionErrorNone;
        if (link.has_value()) {
            https = StringFrom(*link);
            answerSid = StringFrom(sid);
            [self startListenerOutput];
        } else {
            error = [self sessionErrorOr:BGWaveSessionErrorNone];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion != nil) {
                completion(https, answerSid, error);
            }
        });
    });
}

- (void)answerSendFailedForSidHex:(NSString *)sidHex {
    const std::string sid = StdStringFrom(sidHex);
    dispatch_async(self.queue, ^{
        _controller->answerSendFailed(sid, NowUnixSeconds());
    });
}

- (void)declineSidHex:(NSString *)sidHex completion:(void (^)(NSString * _Nullable https))completion {
    const std::string sid = StdStringFrom(sidHex);
    dispatch_async(self.queue, ^{
        const std::optional<std::string> link = _controller->decline(sid, NowUnixSeconds());
        NSString *https = link.has_value() ? StringFrom(*link) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion != nil) {
                completion(https);
            }
        });
    });
}

- (void)stopWithCompletion:(void (^)(NSString * _Nullable https))completion {
    dispatch_async(self.queue, ^{
        const std::optional<std::string> link = _controller->stop(NowUnixSeconds());
        NSString *https = link.has_value() ? StringFrom(*link) : nil;
        [self stopListenerOutput];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion != nil) {
                completion(https);
            }
        });
    });
}

- (void)retryWithCompletion:(void (^)(BOOL started))completion {
    dispatch_async(self.queue, ^{
        const bool started = _controller->retry(NowUnixSeconds());
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion != nil) {
                completion(started ? YES : NO);
            }
        });
    });
}

- (void)dismiss {
    dispatch_async(self.queue, ^{
        _controller->dismiss();
    });
}

- (void)cancelLinkForSidHex:(NSString *)sidHex completion:(void (^)(NSString * _Nullable https))completion {
    const std::string sid = StdStringFrom(sidHex);
    dispatch_async(self.queue, ^{
        const std::optional<std::string> link = _controller->cancelLink(sid, NowUnixSeconds());
        NSString *https = link.has_value() ? StringFrom(*link) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion != nil) {
                completion(https);
            }
        });
    });
}

- (void)resetAccountId:(NSString *)accountId {
    const std::string account = StdStringFrom(accountId);
    dispatch_async(self.queue, ^{
        _controller->resetAccount(account, NowUnixSeconds());
    });
}

- (void)noteOfferMessageForAccountId:(NSString *)accountId
                              chatId:(int64_t)chatId
                           messageId:(int64_t)messageId
                              sidHex:(NSString *)sidHex {
    const std::string account = StdStringFrom(accountId);
    const std::string sid = StdStringFrom(sidHex);
    dispatch_async(self.queue, ^{
        _controller->noteOfferMessage(account, chatId, messageId, sid);
    });
}

- (void)offerMessageGoneForAccountId:(NSString *)accountId
                              chatId:(int64_t)chatId
                           messageId:(int64_t)messageId
                    stillValidSidHex:(nullable NSString *)stillValidSidHex {
    const std::string account = StdStringFrom(accountId);
    const std::string stillValid = stillValidSidHex != nil ? StdStringFrom(stillValidSidHex) : std::string();
    dispatch_async(self.queue, ^{
        _controller->onOfferMessageGone(account, chatId, messageId, stillValid, NowUnixSeconds());
    });
}

- (void)invalidate {
    dispatch_async(self.queue, ^{
        // Stops the change callbacks first, so that the reset does not reach the UI. The reset closes the wave, and the
        // will-close callback detaches the host tap before the native session is released.
        _controller->setChangeListener(nullptr);
        _controller->reset(NowUnixSeconds());
        _controller->setSessionWillCloseListener(nullptr);
        [self stopTimer];
        [self stopListenerOutput];
    });
}

#pragma mark - Owner queue

- (BGWaveSnapshotModel *)makeSnapshot {
    const beygram::wave::BGWaveSnapshot native = _controller->snapshot();
    BGWaveSessionModel *session = nil;
    if (native.session.has_value()) {
        const beygram::wave::BGWaveSessionState &state = *native.session;
        BOOL hint = NO;
        if (state.phase == beygram::wave::BGWavePhase::Failed && _slot->current != nullptr) {
            hint = _slot->current->failureKind() == beygram::wave::WaveFailureKind::LocalNetworkSuspected ? YES : NO;
        }
        session = [[BGWaveSessionModel alloc] initWithRole:SessionRoleFrom(state.role)
                                                 accountId:StringFrom(state.accountId)
                                                    chatId:state.chatId
                                                    peerId:state.peerId
                                                    sidHex:StringFrom(state.sidHex)
                                                     phase:PhaseFrom(state.phase)
                                                     error:ErrorFrom(state.error)
                                                     route:RouteFrom(state.route)
                                         sourceUnsupported:state.sourceUnsupported ? YES : NO
                                          localNetworkHint:hint];
    }
    NSMutableArray<BGWaveInviteModel *> *invites = [NSMutableArray arrayWithCapacity:(NSUInteger)native.invites.size()];
    for (const beygram::wave::BGWaveInviteEntry &entry : native.invites) {
        [invites addObject:[[BGWaveInviteModel alloc] initWithSidHex:StringFrom(entry.sidHex)
                                                           accountId:StringFrom(entry.invite.accountId)
                                                              chatId:entry.invite.chatId
                                                            senderId:entry.invite.senderId
                                                                 uri:StringFrom(entry.invite.uri)
                                                           expiresAt:entry.invite.expiresAt
                                                              status:InviteStatusFrom(entry.invite.status)]];
    }
    return [[BGWaveSnapshotModel alloc] initWithSession:session invites:invites];
}

// Called by the controller after every change of the wave or of the invitations.
- (void)deliverChange {
    BGWaveSnapshotModel *snapshot = [self makeSnapshot];
    dispatch_async(dispatch_get_main_queue(), ^{
        id<BGWaveSessionControllerDelegate> delegate = self.delegate;
        if ([delegate respondsToSelector:@selector(waveSessionController:didChangeSnapshot:)]) {
            [delegate waveSessionController:self didChangeSnapshot:snapshot];
        }
    });
    [self updateTimers];
}

// Called by the controller just before a native session is released.
- (void)willCloseNativeSession {
    [self stopListenerOutput];
    if (self.hostTapAttached) {
        self.hostTapAttached = NO;
        void (^handler)(void * _Nullable) = self.hostTapHandler;
        // Synchronous on purpose: the tap must be detached before the runtime is released. The main queue never waits on
        // this queue, so the wait cannot cycle.
        dispatch_sync(dispatch_get_main_queue(), ^{
            if (handler != nil) {
                handler(NULL);
            }
        });
    }
}

- (void)updateTimers {
    const bool hasWave = _controller->snapshot().session.has_value();
    if (hasWave && self.timer == nil) {
        [self startTimer];
    } else if (!hasWave && self.timer != nil) {
        [self stopTimer];
    }
}

- (void)startTimer {
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.queue);
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), kPumpIntervalNs, kPumpLeewayNs);
    // The handler holds the facade until the timer is cancelled, which happens when the wave ends or on invalidate.
    dispatch_source_set_event_handler(timer, ^{
        [self tick];
    });
    dispatch_resume(timer);
    self.timer = timer;
}

- (void)stopTimer {
    if (self.timer != nil) {
        dispatch_source_cancel(self.timer);
        self.timer = nil;
    }
}

- (void)tick {
    _controller->pump([[NSProcessInfo processInfo] systemUptime]);
    self.tickCount += 1;
    if (self.tickCount % kPollEveryTicks != 0) {
        return;
    }
    const std::vector<std::string> links = _controller->poll(NowUnixSeconds());
    for (const std::string &link : links) {
        NSString *https = StringFrom(link);
        dispatch_async(dispatch_get_main_queue(), ^{
            void (^handler)(NSString *) = self.outboundLinkHandler;
            if (handler != nil) {
                handler(https);
            }
        });
    }
}

- (void)attachHostTapIfNeeded {
    RuntimeNativeSession *native = _slot->current;
    if (native == nullptr || !native->isHost() || self.hostTapAttached) {
        return;
    }
    self.hostTapAttached = YES;
    void *tap = native->hostTapPointer();
    dispatch_async(dispatch_get_main_queue(), ^{
        void (^handler)(void * _Nullable) = self.hostTapHandler;
        if (handler != nil) {
            handler(tap);
        }
    });
}

- (void)startListenerOutput {
    RuntimeNativeSession *native = _slot->current;
    if (native == nullptr || native->isHost() || self.listenerOutput != nil) {
        return;
    }
    // The pull block keeps the runtime pointer. The will-close callback stops the output before the runtime is released.
    beygram::wave::BGWaveRuntime *runtime = &native->runtime();
    BGWaveListenerOutput *output = [[BGWaveListenerOutput alloc]
        initWithPullBlock:^NSUInteger(float *outInterleavedStereo, NSUInteger frames, uint32_t sampleRate) {
            return (NSUInteger)runtime->pullListenerPcm(outInterleavedStereo, frames, sampleRate);
        }];
    NSError *error = nil;
    if (![output startWithError:&error]) {
        // Logged without any link text. The wave continues without sound until the next join.
        NSLog(@"BGWave: the listener output did not start (%@)", error.localizedDescription);
        return;
    }
    self.listenerOutput = output;
}

- (void)stopListenerOutput {
    if (self.listenerOutput != nil) {
        [self.listenerOutput stop];
        self.listenerOutput = nil;
    }
}

- (NSString *)currentSidHex {
    const beygram::wave::BGWaveSnapshot native = _controller->snapshot();
    return native.session.has_value() ? StringFrom(native.session->sidHex) : @"";
}

- (BGWaveSessionError)sessionErrorOr:(BGWaveSessionError)fallback {
    const beygram::wave::BGWaveSnapshot native = _controller->snapshot();
    if (native.session.has_value() && native.session->error != beygram::wave::BGWaveError::None) {
        return ErrorFrom(native.session->error);
    }
    return fallback;
}

@end
