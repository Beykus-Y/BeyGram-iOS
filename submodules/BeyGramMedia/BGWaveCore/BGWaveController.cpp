#include "BGWaveController.hpp"

#include <algorithm>
#include <utility>

namespace beygram::wave {
namespace bw = bgmedia::wave;

namespace {

// Fixed control nonces, as on Android. Replay protection is per (session, type), so each control type counts on its own.
constexpr std::uint64_t kDeclineNonce = 1;      // a Cancel from a listener who declined
constexpr std::uint64_t kStopNonce = 2;         // an End, or a Cancel before the answer, from a stop
constexpr std::uint64_t kAbortCancelNonce = 3;  // a Cancel for an offer whose send outlived the local stop

constexpr std::size_t kMaxPolledLinks = 8;
constexpr std::size_t kMaxOfferMessages = 256;
constexpr std::size_t kMaxPeerKeys = 256;
constexpr std::size_t kMaxPeerInvites = 5;
constexpr std::int64_t kPeerInviteWindowSeconds = 600;
// Added to an offer's expiry before its tombstone may be dropped. Android uses 300 seconds. The core's own clock-skew
// limit is 60 seconds, so this keeps tombstones longer than strictly needed, which is the safe direction.
constexpr std::int64_t kClockSkewSeconds = 300;

bool isAwaiting(BGWavePhase phase) noexcept {
    return phase == BGWavePhase::Offering || phase == BGWavePhase::AwaitingAnswer;
}

bool isSettled(BGWavePhase phase) noexcept {
    return phase == BGWavePhase::Failed || phase == BGWavePhase::Ended;
}

BGWaveRoute routeOf(bw::WaveTransportRoute route) noexcept {
    switch (route) {
    case bw::WaveTransportRoute::P2P:
        return BGWaveRoute::Direct;
    case bw::WaveTransportRoute::ExternalCall:
        return BGWaveRoute::ExternalCall;
    case bw::WaveTransportRoute::None:
        break;
    }
    return BGWaveRoute::None;
}

BGWaveSessionState bindingOf(BGWaveRole role,
                             const std::string& accountId,
                             std::int64_t chatId,
                             std::int64_t peerId,
                             std::string_view sidHex,
                             BGWavePhase phase) {
    BGWaveSessionState state;
    state.role = role;
    state.accountId = accountId;
    state.chatId = chatId;
    state.peerId = peerId;
    state.sidHex = std::string(sidHex);
    state.phase = phase;
    return state;
}

// True when the key is "<sidHex>:<type>" for this session.
bool isKeyOfSession(const std::string& key, std::string_view sidHex) {
    return key.size() > sidHex.size() && key.compare(0, sidHex.size(), sidHex) == 0 && key[sidHex.size()] == ':';
}

std::string nonceKey(std::string_view sidHex, bw::WaveSignalType type) {
    return std::string(sidHex) + ":" + std::to_string(static_cast<unsigned>(type));
}

// The portable native session: a BGWaveSession, with the codec and transport the caller injected.
class BGWaveCoreSession final : public BGWaveNativeSession {
public:
    explicit BGWaveCoreSession(std::unique_ptr<BGWaveSession> session) : session_(std::move(session)) {}

    bool startOffer(std::int64_t nowUnixSeconds, std::int64_t offerTtlSeconds) override {
        return session_->startOffer(nowUnixSeconds, offerTtlSeconds);
    }

    bool handleRemote(std::string_view link, std::int64_t nowUnixSeconds) override {
        return session_->acceptInvite(link, nowUnixSeconds);
    }

    std::optional<std::string> pollOutbound() override { return session_->pollOutboundInvite(); }

    BGWaveNativeStatus status() const override {
        BGWaveNativeStatus result;
        result.state = session_->state();
        result.route = session_->route();
        result.lastError = session_->lastError();
        return result;
    }

    void stop(bool emitEnd, std::int64_t nowUnixSeconds) override { session_->stop(emitEnd, nowUnixSeconds); }

    bool reconnect(std::int64_t nowUnixSeconds) override { return session_->reconnect(nowUnixSeconds); }

    void process(double monotonicSeconds) override { session_->process(monotonicSeconds); }

private:
    std::unique_ptr<BGWaveSession> session_;
};

}  // namespace

std::unique_ptr<BGWaveNativeSession> makeBGWaveCoreSession(BGWaveSession::Options options,
                                                           std::shared_ptr<bw::IWaveAudioCodec> codec,
                                                           std::shared_ptr<bw::IWaveTransport> transport) {
    return std::make_unique<BGWaveCoreSession>(
        std::make_unique<BGWaveSession>(options, std::move(codec), std::move(transport)));
}

std::string_view bgWaveErrorKey(BGWaveError error) noexcept {
    switch (error) {
    case BGWaveError::Unavailable:
        return "bgwave_error_unavailable";
    case BGWaveError::SendFailed:
        return "bgwave_error_send_failed";
    case BGWaveError::NoConnection:
        return "bgwave_error_no_connection";
    case BGWaveError::Busy:
        return "bgwave_error_busy";
    case BGWaveError::Expired:
        return "bgwave_error_expired";
    case BGWaveError::Rejected:
        return "bgwave_error_rejected";
    case BGWaveError::OfferTooLarge:
        return "bgwave_error_offer_too_large";
    case BGWaveError::None:
        break;
    }
    return {};
}

BGWaveController::BGWaveController(BGWaveSessionFactory createSession, BGWaveControllerOptions options)
    : createSession_(std::move(createSession)), options_(std::move(options)) {
    if (!options_.decode) {
        options_.decode = [](std::string_view link, std::int64_t nowUnixSeconds) {
            return decodeInviteFields(link, nowUnixSeconds);
        };
    }
    if (!options_.encodeControl) {
        options_.encodeControl = [](bw::WaveSignalType type,
                                    std::string_view sidHex,
                                    std::int64_t nowUnixSeconds,
                                    std::uint64_t nonce) {
            return encodeControlInvite(type, sidHex, nowUnixSeconds, nonce);
        };
    }
}

BGWaveController::~BGWaveController() {
    closeSession(false, 0);
}

void BGWaveController::setChangeListener(BGWaveChangeListener listener) {
    changeListener_ = std::move(listener);
}

void BGWaveController::setSessionWillCloseListener(std::function<void()> listener) {
    sessionWillClose_ = std::move(listener);
}

BGWaveSnapshot BGWaveController::snapshot() const {
    BGWaveSnapshot result;
    result.session = state_;
    result.invites = invites_;
    return result;
}

std::optional<std::string> BGWaveController::startHosting(const std::string& accountId,
                                                          std::int64_t chatId,
                                                          std::int64_t peerId,
                                                          std::int64_t nowUnixSeconds) {
    tick(nowUnixSeconds);
    if (session_) {
        if (!state_ || !isSettled(state_->phase)) {
            fail(BGWaveError::Busy, true, nullptr);
            return std::nullopt;
        }
        markClosed(state_->sidHex);
        closeSession(false, nowUnixSeconds);
        state_.reset();
    }
    const BGWaveSessionState host = bindingOf(BGWaveRole::Host, accountId, chatId, peerId, "", BGWavePhase::Offering);
    setState(host);

    std::unique_ptr<BGWaveNativeSession> created = createSession_ ? createSession_(true) : nullptr;
    if (!created) {
        fail(BGWaveError::Unavailable, false, &host);
        return std::nullopt;
    }
    if (!created->startOffer(nowUnixSeconds, kBGWaveOfferTtlSeconds)) {
        created->stop(false, nowUnixSeconds);
        fail(BGWaveError::Unavailable, false, &host);
        return std::nullopt;
    }
    const std::optional<std::string> uri = created->pollOutbound();
    std::optional<BGWaveInviteFields> decoded;
    std::string link;
    if (uri) {
        decoded = options_.decode(*uri, nowUnixSeconds);
        link = inviteToHttps(*uri);
    }
    if (!decoded || decoded->type != bw::WaveSignalType::Offer || link.empty()) {
        // A valid offer whose https link does not fit is a size problem (too many candidates), not a bad answer.
        const bool tooLarge =
            uri && (uri->size() > kInviteMaxLinkChars ||
                    (decoded && decoded->type == bw::WaveSignalType::Offer && link.empty()));
        created->stop(false, nowUnixSeconds);
        fail(tooLarge ? BGWaveError::OfferTooLarge : BGWaveError::Rejected, false, &host);
        return std::nullopt;
    }
    session_ = std::move(created);
    offerExpiresAt_ = decoded->expiresAt;
    setState(bindingOf(BGWaveRole::Host, accountId, chatId, peerId, decoded->sidHex, BGWavePhase::Offering));
    return link;
}

void BGWaveController::setHostSourceUnsupported(std::string_view sidHex, bool unsupported) {
    if (!state_ || state_->role != BGWaveRole::Host || state_->sidHex != sidHex ||
        state_->sourceUnsupported == unsupported) {
        return;
    }
    state_->sourceUnsupported = unsupported;
    notify();
}

void BGWaveController::offerSent(std::string_view sidHex, bool success, std::int64_t nowUnixSeconds) {
    if (!state_ || state_->sidHex != sidHex || state_->role != BGWaveRole::Host) {
        return;
    }
    // TDLib can accept a send locally and report its failure later, so a success that arrives after the offer moved on
    // is ignored.
    if (success && state_->phase != BGWavePhase::Offering) {
        return;
    }
    if (!success && !isAwaiting(state_->phase)) {
        return;
    }
    if (success) {
        state_->phase = BGWavePhase::AwaitingAnswer;
        notify();
        return;
    }
    closeSession(false, nowUnixSeconds);
    BGWaveSessionState failed = *state_;
    failed.phase = BGWavePhase::Failed;
    failed.error = BGWaveError::SendFailed;
    setState(std::move(failed));
}

void BGWaveController::onMessage(const std::string& accountId,
                                 std::int64_t chatId,
                                 std::int64_t senderId,
                                 bool outgoing,
                                 bool privateChat,
                                 std::string_view uri,
                                 std::int64_t nowUnixSeconds,
                                 std::int64_t messageId) {
    tick(nowUnixSeconds);
    // In a private chat the chat id is the peer's user id, so the message must come from the chat's own peer.
    if (!privateChat || outgoing || senderId != chatId) {
        return;
    }
    const std::optional<BGWaveInviteFields> msg = options_.decode(uri, nowUnixSeconds);
    if (!msg || closed_.contains(msg->sidHex)) {
        return;
    }
    const bool known = findInvite(msg->sidHex) != nullptr;
    const bool current = state_ && state_->sidHex == msg->sidHex;
    // A signal for a session this device never heard of is dropped, so strangers cannot fill the nonce table.
    if (msg->type != bw::WaveSignalType::Offer && !known && !current) {
        return;
    }
    // Check the sender binding before replay protection advances. A different account or chat must never be able to
    // exhaust the real peer's nonce window.
    if (const BGWaveInvite* bound = findInvite(msg->sidHex)) {
        if (bound->accountId != accountId || bound->chatId != chatId || bound->senderId != senderId) {
            return;
        }
    }
    if (state_ && state_->sidHex == msg->sidHex &&
        (state_->accountId != accountId || state_->chatId != chatId || state_->peerId != senderId)) {
        return;
    }
    if (!acceptNonce(msg->sidHex, msg->type, msg->nonce)) {
        return;
    }
    switch (msg->type) {
    case bw::WaveSignalType::Offer:
        onOffer(accountId, chatId, senderId, uri, *msg, nowUnixSeconds, messageId);
        break;
    case bw::WaveSignalType::Answer:
        onAnswer(accountId, chatId, senderId, uri, *msg, nowUnixSeconds);
        break;
    case bw::WaveSignalType::Cancel:
    case bw::WaveSignalType::End:
        onTeardown(accountId, chatId, senderId, *msg);
        break;
    }
}

std::optional<std::string> BGWaveController::join(std::string_view sidHex, std::int64_t nowUnixSeconds) {
    tick(nowUnixSeconds);
    const BGWaveInvite* found = findInvite(sidHex);
    if (!found || found->status != BGWaveInviteStatus::Pending) {
        return std::nullopt;
    }
    const BGWaveInvite invite = *found;
    const std::string sid(sidHex);
    if (session_) {
        if (!state_ || !isSettled(state_->phase)) {
            fail(BGWaveError::Busy, true, nullptr);
            return std::nullopt;
        }
        markClosed(state_->sidHex);
        closeSession(false, nowUnixSeconds);
        state_.reset();
    }
    const BGWaveSessionState listener = bindingOf(BGWaveRole::Listener, invite.accountId, invite.chatId,
                                                  invite.senderId, sid, BGWavePhase::Connecting);
    if (nowUnixSeconds >= invite.expiresAt) {
        BGWaveInvite expired = invite;
        expired.status = BGWaveInviteStatus::Expired;
        setInvite(sid, expired);
        fail(BGWaveError::Expired, false, &listener);
        return std::nullopt;
    }
    setState(listener);

    std::unique_ptr<BGWaveNativeSession> created = createSession_ ? createSession_(false) : nullptr;
    if (!created) {
        fail(BGWaveError::Unavailable, false, &listener);
        return std::nullopt;
    }
    if (!created->handleRemote(invite.uri, nowUnixSeconds)) {
        created->stop(false, nowUnixSeconds);
        fail(BGWaveError::Rejected, false, &listener);
        return std::nullopt;
    }
    const std::optional<std::string> answer = created->pollOutbound();
    std::optional<BGWaveInviteFields> decoded;
    std::string link;
    if (answer) {
        decoded = options_.decode(*answer, nowUnixSeconds);
        link = inviteToHttps(*answer);
    }
    if (!decoded || decoded->type != bw::WaveSignalType::Answer || decoded->sidHex != sid || link.empty()) {
        created->stop(false, nowUnixSeconds);
        fail(BGWaveError::Rejected, false, &listener);
        return std::nullopt;
    }
    return commitJoin(std::move(created), sid, link, nowUnixSeconds);
}

void BGWaveController::answerSendFailed(std::string_view sidHex, std::int64_t nowUnixSeconds) {
    if (!state_ || state_->sidHex != sidHex || state_->role != BGWaveRole::Listener ||
        state_->phase != BGWavePhase::Connecting) {
        return;
    }
    closeSession(false, nowUnixSeconds);
    BGWaveSessionState failed = *state_;
    failed.phase = BGWavePhase::Failed;
    failed.error = BGWaveError::SendFailed;
    setState(std::move(failed));
}

std::optional<std::string> BGWaveController::decline(std::string_view sidHex, std::int64_t nowUnixSeconds) {
    tick(nowUnixSeconds);
    const BGWaveInvite* found = findInvite(sidHex);
    if (!found || found->status != BGWaveInviteStatus::Pending) {
        return std::nullopt;
    }
    BGWaveInvite declined = *found;
    declined.status = BGWaveInviteStatus::Declined;
    markClosed(sidHex);
    setInvite(sidHex, declined);
    return encodeControlLink(bw::WaveSignalType::Cancel, sidHex, nowUnixSeconds, kDeclineNonce);
}

std::optional<std::string> BGWaveController::stop(std::int64_t nowUnixSeconds) {
    tick(nowUnixSeconds);
    if (!state_) {
        closeSession(false, nowUnixSeconds);
        return std::nullopt;
    }
    BGWaveSessionState current = *state_;
    if (isSettled(current.phase)) {
        markClosed(current.sidHex);
        closeSession(false, nowUnixSeconds);
        state_.reset();
        notify();
        return std::nullopt;
    }
    if (current.sidHex.empty()) {
        closeSession(false, nowUnixSeconds);
        state_.reset();
        notify();
        return std::nullopt;
    }
    markClosed(current.sidHex);
    if (current.role == BGWaveRole::Listener) {
        const BGWaveInvite* invite = findInvite(current.sidHex);
        if (invite && invite->status == BGWaveInviteStatus::Pending) {
            BGWaveInvite ended = *invite;
            ended.status = BGWaveInviteStatus::Ended;
            setInvite(current.sidHex, ended);
        }
    }
    const bw::WaveSignalType type =
        isAwaiting(current.phase) ? bw::WaveSignalType::Cancel : bw::WaveSignalType::End;
    closeSession(false, nowUnixSeconds);
    current.phase = BGWavePhase::Ended;
    setState(current);
    return encodeControlLink(type, current.sidHex, nowUnixSeconds, kStopNonce);
}

std::optional<std::string> BGWaveController::stopIfCurrent(const BGWaveSessionState& expected,
                                                           std::int64_t nowUnixSeconds) {
    if (!state_ || state_->sidHex != expected.sidHex || state_->accountId != expected.accountId ||
        state_->chatId != expected.chatId || state_->role != expected.role) {
        return std::nullopt;
    }
    return stop(nowUnixSeconds);
}

bool BGWaveController::retry(std::int64_t nowUnixSeconds) {
    if (!state_ || !session_ ||
        (state_->phase != BGWavePhase::Failed && state_->phase != BGWavePhase::Reconnecting)) {
        return false;
    }
    const bool started = session_->reconnect(nowUnixSeconds);
    BGWaveSessionState next = *state_;
    next.phase = started ? BGWavePhase::Reconnecting : BGWavePhase::Failed;
    next.error = started ? BGWaveError::None : BGWaveError::NoConnection;
    setState(std::move(next));
    return started;
}

void BGWaveController::dismiss() {
    if (!state_ || !isSettled(state_->phase)) {
        return;
    }
    closeSession(false, 0);
    state_.reset();
    notify();
}

std::optional<std::string> BGWaveController::cancelLink(std::string_view sidHex, std::int64_t nowUnixSeconds) {
    if (sidHex.empty()) {
        return std::nullopt;
    }
    return encodeControlLink(bw::WaveSignalType::Cancel, sidHex, nowUnixSeconds, kAbortCancelNonce);
}

void BGWaveController::pump(double monotonicSeconds) {
    if (session_) {
        session_->process(monotonicSeconds);
    }
}

std::vector<std::string> BGWaveController::poll(std::int64_t nowUnixSeconds) {
    tick(nowUnixSeconds);
    std::vector<std::string> outbound;
    if (!state_ || !session_) {
        return outbound;
    }
    if (state_->phase == BGWavePhase::AwaitingAnswer && offerExpiresAt_ > 0 && nowUnixSeconds >= offerExpiresAt_) {
        markClosed(state_->sidHex);
        closeSession(false, nowUnixSeconds);
        state_->phase = BGWavePhase::Ended;
        state_->error = BGWaveError::None;
        notify();
        return outbound;
    }
    while (outbound.size() < kMaxPolledLinks) {
        const std::optional<std::string> next = session_->pollOutbound();
        if (!next) {
            break;
        }
        std::string link = inviteToHttps(*next);
        if (link.empty()) {
            continue;
        }
        if (options_.decode(link, nowUnixSeconds)) {
            outbound.push_back(std::move(link));
        }
    }
    if (!isAwaiting(state_->phase)) {
        const BGWaveNativeStatus status = session_->status();
        const BGWavePhase phase = phaseOf(status.state, state_->phase);
        const BGWaveRoute route = routeOf(status.route);
        const BGWaveError error = phase == BGWavePhase::Failed ? BGWaveError::NoConnection : BGWaveError::None;
        const bool changed = phase != state_->phase || route != state_->route || error != state_->error;
        state_->phase = phase;
        state_->route = route;
        state_->error = error;
        if (changed) {
            notify();
        }
        if (phase == BGWavePhase::Ended) {
            markClosed(state_->sidHex);
            closeSession(false, nowUnixSeconds);
        }
    }
    return outbound;
}

void BGWaveController::reset(std::int64_t nowUnixSeconds) {
    closeSession(false, nowUnixSeconds);
    state_.reset();
    invites_.clear();
    lastNonce_.clear();
    closed_.clear();
    offerMessages_.clear();
    peerInvites_.clear();
    notify();
}

void BGWaveController::resetAccount(const std::string& accountId, std::int64_t nowUnixSeconds) {
    std::vector<std::string> removed;
    for (const BGWaveInviteEntry& entry : invites_) {
        if (entry.invite.accountId == accountId) {
            removed.push_back(entry.sidHex);
        }
    }
    if (!removed.empty()) {
        for (const std::string& sid : removed) {
            eraseInvite(sid);
            forgetOfferMessages(sid);
            eraseNoncesFor(sid);
        }
        notify();
    }
    if (state_ && state_->accountId == accountId) {
        if (!state_->sidHex.empty()) {
            eraseNoncesFor(state_->sidHex);
        }
        closeSession(false, nowUnixSeconds);
        state_.reset();
        notify();
    }
}

void BGWaveController::noteOfferMessage(const std::string& accountId,
                                        std::int64_t chatId,
                                        std::int64_t messageId,
                                        std::string_view sidHex) {
    if (messageId == 0 || sidHex.empty()) {
        return;
    }
    rememberOfferMessage(accountId, chatId, messageId, sidHex);
}

bool BGWaveController::hasOfferMessage(const std::string& accountId,
                                       std::int64_t chatId,
                                       std::int64_t messageId) const {
    return std::any_of(offerMessages_.begin(), offerMessages_.end(), [&](const OfferMessage& message) {
        return message.accountId == accountId && message.chatId == chatId && message.messageId == messageId;
    });
}

void BGWaveController::onOfferMessageGone(const std::string& accountId,
                                          std::int64_t chatId,
                                          std::int64_t messageId,
                                          std::string_view stillValidSidHex,
                                          std::int64_t nowUnixSeconds) {
    tick(nowUnixSeconds);
    const auto found = std::find_if(offerMessages_.begin(), offerMessages_.end(), [&](const OfferMessage& message) {
        return message.accountId == accountId && message.chatId == chatId && message.messageId == messageId;
    });
    if (found == offerMessages_.end()) {
        return;
    }
    const std::string sid = found->sidHex;
    if (sid == stillValidSidHex) {
        return;
    }
    offerMessages_.erase(found);
    if (const BGWaveInvite* invite = findInvite(sid);
        invite && invite->accountId == accountId && invite->chatId == chatId &&
        invite->status == BGWaveInviteStatus::Pending) {
        BGWaveInvite cancelled = *invite;
        cancelled.status = BGWaveInviteStatus::Cancelled;
        markClosed(sid);
        setInvite(sid, cancelled);
    }
    // A session that is already connecting or live does not depend on the message, so it is left alone.
    if (!state_ || state_->sidHex != sid || state_->role != BGWaveRole::Host || state_->accountId != accountId ||
        state_->chatId != chatId || !isAwaiting(state_->phase)) {
        return;
    }
    markClosed(sid);
    closeSession(false, nowUnixSeconds);
    state_->phase = BGWavePhase::Ended;
    state_->error = BGWaveError::None;
    notify();
}

BGWavePhase BGWaveController::phaseOf(bw::WaveSessionState nativeState, BGWavePhase fallback) noexcept {
    switch (nativeState) {
    case bw::WaveSessionState::LiveP2P:
    case bw::WaveSessionState::LiveTelegramCall:
        return BGWavePhase::Live;
    case bw::WaveSessionState::ConnectingP2P:
    case bw::WaveSessionState::ConnectingTelegramCall:
        return BGWavePhase::Connecting;
    case bw::WaveSessionState::P2PFailed:
    case bw::WaveSessionState::Failed:
        return BGWavePhase::Failed;
    case bw::WaveSessionState::Ended:
        return BGWavePhase::Ended;
    case bw::WaveSessionState::Idle:
    case bw::WaveSessionState::Offering:
    case bw::WaveSessionState::AwaitingAnswer:
    case bw::WaveSessionState::OfferingTelegramFallback:
        break;
    }
    return fallback;
}

// The private helpers below run on the owner's queue.

void BGWaveController::tick(std::int64_t nowUnixSeconds) {
    if (nowUnixSeconds > lastNow_) {
        lastNow_ = nowUnixSeconds;
    }
}

void BGWaveController::notify() {
    if (changeListener_) {
        changeListener_(snapshot());
    }
}

void BGWaveController::setState(BGWaveSessionState next) {
    state_ = std::move(next);
    notify();
}

void BGWaveController::setInvite(std::string_view sidHex, BGWaveInvite invite) {
    if (BGWaveInvite* existing = findInvite(sidHex)) {
        *existing = std::move(invite);
    } else {
        invites_.push_back(BGWaveInviteEntry{std::string(sidHex), std::move(invite)});
    }
    notify();
}

void BGWaveController::eraseInvite(std::string_view sidHex) {
    std::erase_if(invites_, [&](const BGWaveInviteEntry& entry) { return entry.sidHex == sidHex; });
}

BGWaveInvite* BGWaveController::findInvite(std::string_view sidHex) {
    for (BGWaveInviteEntry& entry : invites_) {
        if (entry.sidHex == sidHex) {
            return &entry.invite;
        }
    }
    return nullptr;
}

void BGWaveController::markClosed(std::string_view sidHex) {
    if (sidHex.empty()) {
        return;
    }
    const std::string sid(sidHex);
    if (closed_.contains(sid)) {
        return;
    }
    pruneClosed();
    std::int64_t offerExpiry = lastNow_ + kBGWaveOfferTtlSeconds;
    if (const BGWaveInvite* invite = findInvite(sid)) {
        offerExpiry = invite->expiresAt;
    } else if (offerExpiresAt_ > 0 && state_ && state_->sidHex == sid) {
        offerExpiry = offerExpiresAt_;
    }
    closed_[sid] = offerExpiry + kClockSkewSeconds;
}

void BGWaveController::pruneClosed() {
    // Drops only tombstones whose offer the decoder can no longer accept.
    for (auto it = closed_.begin(); it != closed_.end();) {
        if (it->second > lastNow_) {
            ++it;
            continue;
        }
        const std::string key = it->first;
        it = closed_.erase(it);
        if (!findInvite(key)) {
            eraseNoncesFor(key);
        }
    }
}

void BGWaveController::rememberInvite(const std::string& accountId,
                                      std::int64_t chatId,
                                      std::int64_t senderId,
                                      std::string_view uri,
                                      const BGWaveInviteFields& msg,
                                      std::int64_t nowUnixSeconds) {
    if (findInvite(msg.sidHex)) {
        return;
    }
    pruneClosed();
    // Tombstones are full of live sessions: refuse the invitation rather than forget a closed one.
    if (closed_.size() >= options_.maxClosed) {
        return;
    }
    const std::string peerKey = accountId + ":" + std::to_string(senderId);
    std::deque<std::int64_t>& recent = peerInvites_[peerKey];
    const std::int64_t windowStart = nowUnixSeconds - kPeerInviteWindowSeconds;
    while (!recent.empty() && recent.front() <= windowStart) {
        recent.pop_front();
    }
    if (recent.size() >= kMaxPeerInvites) {
        return;
    }
    recent.push_back(nowUnixSeconds);
    if (peerInvites_.size() > kMaxPeerKeys) {
        for (auto it = peerInvites_.begin(); it != peerInvites_.end();) {
            if (it->second.empty() || it->second.back() <= windowStart) {
                it = peerInvites_.erase(it);
            } else {
                ++it;
            }
        }
    }
    while (!invites_.empty() && invites_.size() >= options_.maxInvites) {
        const std::string eldest = invites_.front().sidHex;
        markClosed(eldest);
        eraseInvite(eldest);
        forgetOfferMessages(eldest);
    }
    BGWaveInvite invite;
    invite.accountId = accountId;
    invite.chatId = chatId;
    invite.senderId = senderId;
    invite.uri = std::string(uri);
    invite.expiresAt = msg.expiresAt;
    invite.status = BGWaveInviteStatus::Pending;
    setInvite(msg.sidHex, std::move(invite));
}

void BGWaveController::rememberOfferMessage(const std::string& accountId,
                                            std::int64_t chatId,
                                            std::int64_t messageId,
                                            std::string_view sidHex) {
    const auto existing =
        std::find_if(offerMessages_.begin(), offerMessages_.end(), [&](const OfferMessage& message) {
            return message.accountId == accountId && message.chatId == chatId && message.messageId == messageId;
        });
    if (existing != offerMessages_.end()) {
        existing->sidHex = std::string(sidHex);
    } else {
        offerMessages_.push_back(OfferMessage{accountId, chatId, messageId, std::string(sidHex)});
    }
    while (offerMessages_.size() > kMaxOfferMessages) {
        offerMessages_.erase(offerMessages_.begin());
    }
}

void BGWaveController::forgetOfferMessages(std::string_view sidHex) {
    std::erase_if(offerMessages_, [&](const OfferMessage& message) { return message.sidHex == sidHex; });
}

void BGWaveController::eraseNoncesFor(std::string_view sidHex) {
    const std::string sid(sidHex);
    std::erase_if(lastNonce_, [&](const auto& entry) { return isKeyOfSession(entry.first, sid); });
}

bool BGWaveController::acceptNonce(std::string_view sidHex, bw::WaveSignalType type, std::uint64_t nonce) {
    const std::string key = nonceKey(sidHex, type);
    const auto last = lastNonce_.find(key);
    if (last != lastNonce_.end() && nonce <= last->second) {
        return false;
    }
    lastNonce_[key] = nonce;
    return true;
}

void BGWaveController::fail(BGWaveError error, bool keepSession, const BGWaveSessionState* binding) {
    if (keepSession && state_) {
        return;
    }
    const BGWaveSessionState* source = binding ? binding : (state_ ? &*state_ : nullptr);
    BGWaveSessionState next;
    if (source) {
        next.role = source->role;
        next.accountId = source->accountId;
        next.chatId = source->chatId;
        next.peerId = source->peerId;
        next.sidHex = source->sidHex;
    }
    next.phase = BGWavePhase::Failed;
    next.error = error;
    setState(std::move(next));
}

void BGWaveController::closeSession(bool emitEnd, std::int64_t nowUnixSeconds) {
    offerExpiresAt_ = 0;
    if (!session_) {
        return;
    }
    // The owner detaches anything that points into the session (the PCM tap) before it is released.
    if (sessionWillClose_) {
        sessionWillClose_();
    }
    std::unique_ptr<BGWaveNativeSession> active = std::move(session_);
    active->stop(emitEnd, nowUnixSeconds);
}

std::optional<std::string> BGWaveController::encodeControlLink(bw::WaveSignalType type,
                                                               std::string_view sidHex,
                                                               std::int64_t nowUnixSeconds,
                                                               std::uint64_t nonce) {
    const std::string raw = options_.encodeControl(type, sidHex, nowUnixSeconds, nonce);
    if (raw.empty()) {
        return std::nullopt;
    }
    std::string link = inviteToHttps(raw);
    if (link.empty() || !options_.decode(link, nowUnixSeconds)) {
        return std::nullopt;
    }
    return link;
}

void BGWaveController::onOffer(const std::string& accountId,
                               std::int64_t chatId,
                               std::int64_t senderId,
                               std::string_view uri,
                               const BGWaveInviteFields& msg,
                               std::int64_t nowUnixSeconds,
                               std::int64_t messageId) {
    if (state_ && state_->sidHex == msg.sidHex) {
        // The peer's offer for the session we are reconnecting: hand it to the native session.
        if (session_ && state_->accountId == accountId && state_->chatId == chatId && state_->peerId == senderId &&
            state_->phase == BGWavePhase::Reconnecting) {
            static_cast<void>(session_->handleRemote(uri, nowUnixSeconds));
        }
        return;
    }
    rememberInvite(accountId, chatId, senderId, uri, msg, nowUnixSeconds);
    const BGWaveInvite* remembered = findInvite(msg.sidHex);
    if (messageId != 0 && remembered && remembered->accountId == accountId && remembered->chatId == chatId &&
        remembered->senderId == senderId) {
        rememberOfferMessage(accountId, chatId, messageId, msg.sidHex);
    }
}

void BGWaveController::onAnswer(const std::string& accountId,
                                std::int64_t chatId,
                                std::int64_t senderId,
                                std::string_view uri,
                                const BGWaveInviteFields& msg,
                                std::int64_t nowUnixSeconds) {
    if (!state_ || !session_) {
        return;
    }
    if (state_->sidHex != msg.sidHex || state_->accountId != accountId || state_->chatId != chatId ||
        state_->peerId != senderId) {
        return;
    }
    if (state_->phase == BGWavePhase::Reconnecting) {
        static_cast<void>(session_->handleRemote(uri, nowUnixSeconds));
        return;
    }
    if (state_->role != BGWaveRole::Host || !isAwaiting(state_->phase)) {
        return;
    }
    if (!session_->handleRemote(uri, nowUnixSeconds)) {
        closeSession(false, nowUnixSeconds);
        BGWaveSessionState failed = *state_;
        failed.phase = BGWavePhase::Failed;
        failed.error = BGWaveError::Rejected;
        setState(std::move(failed));
        return;
    }
    BGWaveSessionState connecting = *state_;
    connecting.phase = BGWavePhase::Connecting;
    setState(std::move(connecting));
}

void BGWaveController::onTeardown(const std::string& accountId,
                                  std::int64_t chatId,
                                  std::int64_t senderId,
                                  const BGWaveInviteFields& msg) {
    const BGWaveInviteStatus status =
        msg.type == bw::WaveSignalType::Cancel ? BGWaveInviteStatus::Cancelled : BGWaveInviteStatus::Ended;
    if (const BGWaveInvite* found = findInvite(msg.sidHex)) {
        if (found->accountId == accountId && found->chatId == chatId && found->senderId == senderId) {
            BGWaveInvite updated = *found;
            markClosed(msg.sidHex);
            if (updated.status == BGWaveInviteStatus::Pending || updated.status == BGWaveInviteStatus::Joined) {
                updated.status = status;
                setInvite(msg.sidHex, updated);
            }
        }
    }
    if (!state_ || state_->sidHex != msg.sidHex || state_->accountId != accountId || state_->chatId != chatId ||
        state_->peerId != senderId) {
        return;
    }
    markClosed(msg.sidHex);
    closeSession(false, 0);
    BGWaveSessionState ended = *state_;
    ended.phase = BGWavePhase::Ended;
    setState(std::move(ended));
}

std::optional<std::string> BGWaveController::commitJoin(std::unique_ptr<BGWaveNativeSession> created,
                                                        std::string_view sidHex,
                                                        const std::string& link,
                                                        std::int64_t nowUnixSeconds) {
    const BGWaveInvite* latest = findInvite(sidHex);
    if (!latest || latest->status != BGWaveInviteStatus::Pending || closed_.contains(std::string(sidHex))) {
        created->stop(false, nowUnixSeconds);
        state_.reset();
        notify();
        return std::nullopt;
    }
    BGWaveInvite joined = *latest;
    joined.status = BGWaveInviteStatus::Joined;
    session_ = std::move(created);
    setInvite(sidHex, joined);
    setState(bindingOf(BGWaveRole::Listener, joined.accountId, joined.chatId, joined.senderId, sidHex,
                       BGWavePhase::Connecting));
    return link;
}

}  // namespace beygram::wave
