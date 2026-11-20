// BG Wave controller for iOS: the user's view of one wave, ported from Android's BgWaveController (issue #799).
//
// It is the one place that decides which signalling message to act on. A message counts only when it comes from the
// expected peer, in the expected private chat and account, for the expected session, and only once: replay protection
// is per session and type, with a strictly increasing nonce, as on Android. It drives at most one native session. It
// owns no codec, no transport and no audio. The owner pumps the native session with pump() and polls it with poll().
//
// Threading: not thread-safe. The owner calls every method from one serial queue, and the change listener runs on that
// queue too. The listener must not call back into the controller. startHosting and join gather ICE inside the native
// session (up to the 5 s gathering timeout), so that queue is busy for that long. The UI must not wait on it.
//
// Links: every link the controller returns is in the Telegram-safe https form. Both forms are accepted as input.
#pragma once

#include "BGWaveInvite.hpp"
#include "BGWaveSession.hpp"

#include "bgmedia/wave/WaveSignaling.hpp"
#include "bgmedia/wave/WaveTypes.hpp"

#include <cstddef>
#include <cstdint>
#include <deque>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

namespace beygram::wave {

// The lifetime of an offer. Android uses the same value (OFFER_TTL_SECONDS).
inline constexpr std::int64_t kBGWaveOfferTtlSeconds = 300;

enum class BGWaveRole : std::uint8_t { Host, Listener };

// The phase the UI shows. Names follow Android's BgWavePhase.
enum class BGWavePhase : std::uint8_t { Offering, AwaitingAnswer, Connecting, Live, Reconnecting, Failed, Ended };

enum class BGWaveInviteStatus : std::uint8_t { Pending, Joined, Declined, Cancelled, Ended, Expired };

// Why a wave failed. Set only in the Failed phase. bgWaveErrorKey() gives the localisation key the UI shows.
enum class BGWaveError : std::uint8_t { None, Unavailable, SendFailed, NoConnection, Busy, Expired, Rejected, OfferTooLarge };

// The route as the UI may show it: a status only, never a promise.
enum class BGWaveRoute : std::uint8_t { None, Direct, ExternalCall };

// One wave, as the user sees it. Everything shown is derived from this; no text lives here.
struct BGWaveSessionState {
    BGWaveRole role = BGWaveRole::Host;
    std::string accountId;
    std::int64_t chatId = 0;
    std::int64_t peerId = 0;
    // Empty until the offer exists (host), or while only the invitation is known (listener).
    std::string sidHex;
    BGWavePhase phase = BGWavePhase::Offering;
    BGWaveError error = BGWaveError::None;
    BGWaveRoute route = BGWaveRoute::None;
    // Host only: the playing source cannot be sent into the wave, so the listener hears nothing.
    bool sourceUnsupported = false;
};

// One received invitation, as the card of its message shows it.
struct BGWaveInvite {
    std::string accountId;
    std::int64_t chatId = 0;
    std::int64_t senderId = 0;
    // The link as received, in either form. The native session decodes it on join.
    std::string uri;
    std::int64_t expiresAt = 0;
    BGWaveInviteStatus status = BGWaveInviteStatus::Pending;
};

struct BGWaveInviteEntry {
    std::string sidHex;
    BGWaveInvite invite;
};

// Everything the UI shows, read in one piece. Invitations are in arrival order.
struct BGWaveSnapshot {
    std::optional<BGWaveSessionState> session;
    std::vector<BGWaveInviteEntry> invites;
};

// What the native layer reports about its session.
struct BGWaveNativeStatus {
    bgmedia::wave::WaveSessionState state = bgmedia::wave::WaveSessionState::Idle;
    bgmedia::wave::WaveTransportRoute route = bgmedia::wave::WaveTransportRoute::None;
    // A fixed code name, for logs only. Never shown to the user.
    std::string lastError;
};

// One native session, as the controller uses it. makeBGWaveCoreSession() is the portable implementation.
class BGWaveNativeSession {
public:
    virtual ~BGWaveNativeSession() = default;

    // Host only: starts an offer that lives for offerTtlSeconds and queues it for pollOutbound().
    [[nodiscard]] virtual bool startOffer(std::int64_t nowUnixSeconds, std::int64_t offerTtlSeconds) = 0;
    // Routes one Offer or Answer from the peer, in either link form. The controller never passes it a Cancel or an End.
    [[nodiscard]] virtual bool handleRemote(std::string_view link, std::int64_t nowUnixSeconds) = 0;
    [[nodiscard]] virtual std::optional<std::string> pollOutbound() = 0;
    [[nodiscard]] virtual BGWaveNativeStatus status() const = 0;
    // Stops the native session. The controller sends the peer its own Cancel or End, so emitEnd is passed as false.
    virtual void stop(bool emitEnd, std::int64_t nowUnixSeconds) = 0;
    [[nodiscard]] virtual bool reconnect(std::int64_t nowUnixSeconds) = 0;
    // Drives the pipeline with a monotonic clock in seconds. Never called from a real-time audio thread.
    virtual void process(double monotonicSeconds) = 0;
};

// Creates the native session for a role, or returns null when this platform has none.
using BGWaveSessionFactory = std::function<std::unique_ptr<BGWaveNativeSession>(bool isHost)>;

// Decodes an invite in either form at the given time. Empty when it is invalid, expired or too long.
using BGWaveDecodeFn =
    std::function<std::optional<BGWaveInviteFields>(std::string_view link, std::int64_t nowUnixSeconds)>;

// Encodes a Cancel or an End as a link (either form). Empty when the input is unusable.
using BGWaveEncodeControlFn = std::function<std::string(bgmedia::wave::WaveSignalType type,
                                                        std::string_view sidHex,
                                                        std::int64_t nowUnixSeconds,
                                                        std::uint64_t nonce)>;

using BGWaveChangeListener = std::function<void(const BGWaveSnapshot& snapshot)>;

struct BGWaveControllerOptions {
    // Empty means decodeInviteFields and encodeControlInvite. Tests inject fakes.
    BGWaveDecodeFn decode;
    BGWaveEncodeControlFn encodeControl;
    // At most this many invitations are kept. The eldest is retired when a new one arrives.
    std::size_t maxInvites = 50;
    // Closed sessions remembered. When the table is full of live ones, new invitations are refused instead.
    std::size_t maxClosed = 512;
};

// The portable native session: a BGWaveSession over an injected codec and transport.
[[nodiscard]] std::unique_ptr<BGWaveNativeSession> makeBGWaveCoreSession(
    BGWaveSession::Options options,
    std::shared_ptr<bgmedia::wave::IWaveAudioCodec> codec,
    std::shared_ptr<bgmedia::wave::IWaveTransport> transport);

// The localisation key for a failure. These are the same keys as Android's BgWaveErrors.
[[nodiscard]] std::string_view bgWaveErrorKey(BGWaveError error) noexcept;

class BGWaveController final {
public:
    BGWaveController(BGWaveSessionFactory createSession, BGWaveControllerOptions options = {});
    // Releases the native session without sending anything.
    ~BGWaveController();

    BGWaveController(const BGWaveController&) = delete;
    BGWaveController& operator=(const BGWaveController&) = delete;

    // Called after every change of the session or of the invitations.
    void setChangeListener(BGWaveChangeListener listener);
    // Called just before a native session is released, so that a PCM tap can be detached first.
    void setSessionWillCloseListener(std::function<void()> listener);

    [[nodiscard]] BGWaveSnapshot snapshot() const;

    // Host: starts a wave. Returns the https offer to send to chatId, or nothing with the reason in snapshot().session.
    [[nodiscard]] std::optional<std::string> startHosting(const std::string& accountId,
                                                          std::int64_t chatId,
                                                          std::int64_t peerId,
                                                          std::int64_t nowUnixSeconds);
    // Host: records whether the playing source can be sent into the wave. No-op for other roles or unchanged values.
    void setHostSourceUnsupported(std::string_view sidHex, bool unsupported);
    // The offer was handed to Telegram, or not. A failed send tears the wave down.
    void offerSent(std::string_view sidHex, bool success, std::int64_t nowUnixSeconds);

    // Feeds one Telegram message that may carry a wave link. Outgoing messages never drive a wave. privateChat must be
    // true only for an ordinary one-to-one chat (not a group, channel or secret chat).
    void onMessage(const std::string& accountId,
                   std::int64_t chatId,
                   std::int64_t senderId,
                   bool outgoing,
                   bool privateChat,
                   std::string_view uri,
                   std::int64_t nowUnixSeconds,
                   std::int64_t messageId = 0);

    // Listener: joins a pending invitation. Returns the https answer to send, or nothing with the reason in snapshot().
    [[nodiscard]] std::optional<std::string> join(std::string_view sidHex, std::int64_t nowUnixSeconds);
    // The answer could not be handed to Telegram, so the wave cannot start.
    void answerSendFailed(std::string_view sidHex, std::int64_t nowUnixSeconds);
    // Listener: declines a pending invitation. Returns the https Cancel to tell the host, or nothing.
    [[nodiscard]] std::optional<std::string> decline(std::string_view sidHex, std::int64_t nowUnixSeconds);

    // Either side: stops the wave. Returns the https Cancel (before an answer) or End for the peer, or nothing.
    [[nodiscard]] std::optional<std::string> stop(std::int64_t nowUnixSeconds);
    // Stops only the wave the caller captured (same role, account, chat and session), never a replacement.
    [[nodiscard]] std::optional<std::string> stopIfCurrent(const BGWaveSessionState& expected,
                                                           std::int64_t nowUnixSeconds);
    // Retry after a failure: asks the native session to reconnect. Returns whether it started.
    [[nodiscard]] bool retry(std::int64_t nowUnixSeconds);
    // Clears a finished or failed wave from the screen.
    void dismiss();
    // A Cancel for an offer whose send finished after stop() had already ended the local wave.
    [[nodiscard]] std::optional<std::string> cancelLink(std::string_view sidHex, std::int64_t nowUnixSeconds);

    // Drives the native session. Call about every 10 ms while a wave runs, from the owner's queue.
    void pump(double monotonicSeconds);
    // Polls the native session about once a second. Returns the https links to send.
    [[nodiscard]] std::vector<std::string> poll(std::int64_t nowUnixSeconds);

    // Tears everything down (tests, or a full app reset).
    void reset(std::int64_t nowUnixSeconds);
    // Clears one account's invitations, and closes the wave only if it belongs to that account.
    void resetAccount(const std::string& accountId, std::int64_t nowUnixSeconds);

    // Remembers that the offer of a session is a Telegram message, so that deleting or editing it can retire the offer.
    void noteOfferMessage(const std::string& accountId,
                          std::int64_t chatId,
                          std::int64_t messageId,
                          std::string_view sidHex);
    [[nodiscard]] bool hasOfferMessage(const std::string& accountId, std::int64_t chatId, std::int64_t messageId) const;
    // An offer message was deleted or edited. stillValidSidHex is the session it carries now, or empty for none.
    void onOfferMessageGone(const std::string& accountId,
                            std::int64_t chatId,
                            std::int64_t messageId,
                            std::string_view stillValidSidHex,
                            std::int64_t nowUnixSeconds);

    // Maps a native state onto the UI phase. Native states with no UI phase keep the fallback.
    [[nodiscard]] static BGWavePhase phaseOf(bgmedia::wave::WaveSessionState nativeState, BGWavePhase fallback) noexcept;

private:
    struct OfferMessage {
        std::string accountId;
        std::int64_t chatId = 0;
        std::int64_t messageId = 0;
        std::string sidHex;
    };

    void tick(std::int64_t nowUnixSeconds);
    void notify();
    void setState(BGWaveSessionState next);
    void setInvite(std::string_view sidHex, BGWaveInvite invite);
    void eraseInvite(std::string_view sidHex);
    [[nodiscard]] BGWaveInvite* findInvite(std::string_view sidHex);
    void markClosed(std::string_view sidHex);
    void pruneClosed();
    void rememberInvite(const std::string& accountId,
                        std::int64_t chatId,
                        std::int64_t senderId,
                        std::string_view uri,
                        const BGWaveInviteFields& msg,
                        std::int64_t nowUnixSeconds);
    void rememberOfferMessage(const std::string& accountId,
                              std::int64_t chatId,
                              std::int64_t messageId,
                              std::string_view sidHex);
    void forgetOfferMessages(std::string_view sidHex);
    void eraseNoncesFor(std::string_view sidHex);
    [[nodiscard]] bool acceptNonce(std::string_view sidHex, bgmedia::wave::WaveSignalType type, std::uint64_t nonce);
    // Ends the wave with a failure. With keepSession, an existing state is left as it is (the Busy case). The binding,
    // when given, names the wave the failure belongs to. Otherwise the current wave's identity is kept.
    void fail(BGWaveError error, bool keepSession, const BGWaveSessionState* binding);
    void closeSession(bool emitEnd, std::int64_t nowUnixSeconds);
    [[nodiscard]] std::optional<std::string> encodeControlLink(bgmedia::wave::WaveSignalType type,
                                                               std::string_view sidHex,
                                                               std::int64_t nowUnixSeconds,
                                                               std::uint64_t nonce);
    void onOffer(const std::string& accountId,
                 std::int64_t chatId,
                 std::int64_t senderId,
                 std::string_view uri,
                 const BGWaveInviteFields& msg,
                 std::int64_t nowUnixSeconds,
                 std::int64_t messageId);
    void onAnswer(const std::string& accountId,
                  std::int64_t chatId,
                  std::int64_t senderId,
                  std::string_view uri,
                  const BGWaveInviteFields& msg,
                  std::int64_t nowUnixSeconds);
    void onTeardown(const std::string& accountId,
                    std::int64_t chatId,
                    std::int64_t senderId,
                    const BGWaveInviteFields& msg);
    [[nodiscard]] std::optional<std::string> commitJoin(std::unique_ptr<BGWaveNativeSession> created,
                                                        std::string_view sidHex,
                                                        const std::string& link,
                                                        std::int64_t nowUnixSeconds);

    BGWaveSessionFactory createSession_;
    BGWaveControllerOptions options_;
    BGWaveChangeListener changeListener_;
    std::function<void()> sessionWillClose_;

    std::optional<BGWaveSessionState> state_;
    std::unique_ptr<BGWaveNativeSession> session_;
    std::int64_t offerExpiresAt_ = 0;
    std::vector<BGWaveInviteEntry> invites_;
    // Highest nonce accepted per session and type ("sid:type"). A repeat or an older one is a replay.
    std::unordered_map<std::string, std::uint64_t> lastNonce_;
    // Closed sessions, each remembered until this time (its offer's expiry plus clock skew).
    std::unordered_map<std::string, std::int64_t> closed_;
    std::int64_t lastNow_ = 0;
    std::vector<OfferMessage> offerMessages_;
    // Per "account:sender": when its recent invitations arrived, for the rate limit.
    std::unordered_map<std::string, std::deque<std::int64_t>> peerInvites_;
};

}  // namespace beygram::wave
