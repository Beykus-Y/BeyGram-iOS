// Host tests for the BG Wave iOS controller. The scenarios follow Android's BgWaveControllerTest: a fake native session
// and a fake invite format keep them independent of the codec. The later checks run the controller over real core
// sessions (BGWaveSession, Pcm16WaveCodec and SimulatedWaveTransport), and check the control invites against the golden
// fixtures. Plain C++20 with a CHECK macro: a failed check prints its line, and the process exits with 1.
#include "../BGWaveController.hpp"
#include "../BGWaveInvite.hpp"
#include "../BGWaveSession.hpp"

#include "bgmedia/wave/WaveCodec.hpp"
#include "bgmedia/wave/WaveSignaling.hpp"
#include "bgmedia/wave/WaveTransport.hpp"
#include "bgmedia/wave/WaveTypes.hpp"

#include <array>
#include <cstdint>
#include <cstdio>
#include <deque>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace {

namespace bw = bgmedia::wave;
namespace bg = beygram::wave;

int gFailures = 0;

#define CHECK(condition)                                                                       \
    do {                                                                                       \
        if (!(condition)) {                                                                    \
            std::fprintf(stderr, "%s:%d: check failed: %s\n", __FILE__, __LINE__, #condition); \
            ++gFailures;                                                                       \
        }                                                                                      \
    } while (false)

// Golden invites from BG-Media tests/fixtures/wave_v1, the same strings as BGWaveCoreTests.cpp.
constexpr const char* kOfferBg = "bg://wave/v1/QlcBARAhMkNUZXaHmKm6y9zt_g8AAAAAaRU-wAAAAABpFT84AAAABwAAAAAAAAABCGJnd0hvc3QxGGhvc3RJY2VTZWNyZXRQd2QxMjM0NTY3OAdzaGEtMjU2AQARIjNEVWZ3iJmqu8zd7v8AESIzRFVmd4iZqrvM3e7_AAMBMQEAfn8e_8NQAcAAAgoBMgEAfn4e_8NRAiABDbgAAAAAAAAAAAAAABABMwEAZH8e_8NSAxNhMWIyYzNkNC0wMDAxLmxvY2Fs";
constexpr const char* kOfferHttps = "https://beygram.beykus.fun/#bgwave-v1.QlcBARAhMkNUZXaHmKm6y9zt_g8AAAAAaRU-wAAAAABpFT84AAAABwAAAAAAAAABCGJnd0hvc3QxGGhvc3RJY2VTZWNyZXRQd2QxMjM0NTY3OAdzaGEtMjU2AQARIjNEVWZ3iJmqu8zd7v8AESIzRFVmd4iZqrvM3e7_AAMBMQEAfn8e_8NQAcAAAgoBMgEAfn4e_8NRAiABDbgAAAAAAAAAAAAAABABMwEAZH8e_8NSAxNhMWIyYzNkNC0wMDAxLmxvY2Fs";
constexpr const char* kCancelBg = "bg://wave/v1/QlcBAxAhMkNUZXaHmKm6y9zt_g8AAAAAaRU-ygAAAABpFT8GAAAAAAAAAAAAAAADAAAHc2hhLTI1NgAAAAA";
constexpr const char* kCancelHttps = "https://beygram.beykus.fun/#bgwave-v1.QlcBAxAhMkNUZXaHmKm6y9zt_g8AAAAAaRU-ygAAAABpFT8GAAAAAAAAAAAAAAADAAAHc2hhLTI1NgAAAAA";
constexpr const char* kEndHttps = "https://beygram.beykus.fun/#bgwave-v1.QlcBBBAhMkNUZXaHmKm6y9zt_g8AAAAAaRU_GgAAAABpFT9WAAAAAAAAAAAAAAAEAAAHc2hhLTI1NgAAAAA";

constexpr const char* kSid = "102132435465768798a9bacbdcedfe0f";
constexpr const char* kOtherSid = "ffffffffffffffffffffffffffffffff";
constexpr std::int64_t kFixtureNow = 1763000050;
constexpr std::int64_t kNow = 1000;
constexpr std::int64_t kT0 = 1763000000;

std::optional<std::int64_t> parseNumber(std::string_view text) {
    if (text.empty() || text.size() > 18) {
        return std::nullopt;
    }
    std::int64_t value = 0;
    for (const char c : text) {
        if (c < '0' || c > '9') {
            return std::nullopt;
        }
        value = value * 10 + (c - '0');
    }
    return value;
}

// The fake invite format of the scenarios: "<prefix><type>-<sid>-<nonce>-<exp>", in either form. An expired link is refused.
std::optional<bg::BGWaveInviteFields> fakeDecode(std::string_view link, std::int64_t now) {
    std::string_view body = link;
    if (body.substr(0, bg::kInviteUriPrefix.size()) == bg::kInviteUriPrefix) {
        body.remove_prefix(bg::kInviteUriPrefix.size());
    } else if (body.substr(0, bg::kInviteHttpsPrefix.size()) == bg::kInviteHttpsPrefix) {
        body.remove_prefix(bg::kInviteHttpsPrefix.size());
    } else {
        return std::nullopt;
    }
    std::vector<std::string_view> parts;
    std::size_t start = 0;
    for (std::size_t i = 0; i <= body.size(); ++i) {
        if (i == body.size() || body[i] == '-') {
            parts.push_back(body.substr(start, i - start));
            start = i + 1;
        }
    }
    if (parts.size() != 4) {
        return std::nullopt;
    }
    const std::optional<std::int64_t> type = parseNumber(parts[0]);
    const std::optional<std::int64_t> nonce = parseNumber(parts[2]);
    const std::optional<std::int64_t> exp = parseNumber(parts[3]);
    if (!type || !nonce || !exp || now >= *exp) {
        return std::nullopt;
    }
    bg::BGWaveInviteFields fields;
    fields.type = static_cast<bw::WaveSignalType>(*type);
    fields.sidHex = std::string(parts[1]);
    fields.expiresAt = *exp;
    fields.caps = 3;
    fields.nonce = static_cast<std::uint64_t>(*nonce);
    fields.candidateCount = 1;
    return fields;
}

std::string inviteLink(int type, std::uint64_t nonce = 1, std::int64_t exp = kNow + 300, std::string_view sid = kSid) {
    return std::string(bg::kInviteUriPrefix) + std::to_string(type) + "-" + std::string(sid) + "-" +
           std::to_string(nonce) + "-" + std::to_string(exp);
}

class FakeSession;

// What the fake native layer does and records. Tests set the outbound queue before the session it feeds is created.
struct Harness {
    std::deque<std::string> outbound;
    bool accept = true;
    bool available = true;
    bw::WaveSessionState nativeState = bw::WaveSessionState::Idle;
    bw::WaveTransportRoute nativeRoute = bw::WaveTransportRoute::None;
    std::vector<std::string> remote;
    std::vector<std::string> events;
    FakeSession* live = nullptr;
    int stops = 0;
    int destroyed = 0;
};

class FakeSession final : public bg::BGWaveNativeSession {
public:
    explicit FakeSession(Harness& harness) : harness_(harness), outbound_(harness.outbound) {
        harness_.live = this;
    }

    ~FakeSession() override {
        if (harness_.live == this) {
            harness_.live = nullptr;
        }
        ++harness_.destroyed;
        harness_.events.emplace_back("destroyed");
    }

    bool startOffer(std::int64_t, std::int64_t) override { return true; }

    bool handleRemote(std::string_view link, std::int64_t) override {
        harness_.remote.emplace_back(link);
        return harness_.accept;
    }

    std::optional<std::string> pollOutbound() override {
        if (outbound_.empty()) {
            return std::nullopt;
        }
        std::string next = outbound_.front();
        outbound_.pop_front();
        return next;
    }

    bg::BGWaveNativeStatus status() const override {
        bg::BGWaveNativeStatus result;
        result.state = harness_.nativeState;
        result.route = harness_.nativeRoute;
        return result;
    }

    void stop(bool, std::int64_t) override {
        ++harness_.stops;
        harness_.events.emplace_back("stop");
    }

    bool reconnect(std::int64_t) override { return true; }

    void process(double) override {}

private:
    Harness& harness_;
    std::deque<std::string> outbound_;
};

bg::BGWaveSessionFactory fakeFactory(Harness& harness) {
    return [&harness](bool) -> std::unique_ptr<bg::BGWaveNativeSession> {
        if (!harness.available) {
            return nullptr;
        }
        return std::make_unique<FakeSession>(harness);
    };
}

bg::BGWaveControllerOptions fakeOptions(std::size_t maxInvites = 50) {
    bg::BGWaveControllerOptions options;
    options.decode = [](std::string_view link, std::int64_t now) { return fakeDecode(link, now); };
    options.encodeControl = [](bw::WaveSignalType type, std::string_view sid, std::int64_t now, std::uint64_t nonce) {
        return inviteLink(static_cast<int>(type), nonce, now + 300, sid);
    };
    options.maxInvites = maxInvites;
    return options;
}

std::unique_ptr<bg::BGWaveController> makeController(Harness& harness, std::size_t maxInvites = 50) {
    return std::make_unique<bg::BGWaveController>(fakeFactory(harness), fakeOptions(maxInvites));
}

std::optional<bg::BGWavePhase> currentPhase(const bg::BGWaveController& c) {
    const bg::BGWaveSnapshot snap = c.snapshot();
    if (!snap.session) {
        return std::nullopt;
    }
    return snap.session->phase;
}

std::optional<bg::BGWaveError> currentError(const bg::BGWaveController& c) {
    const bg::BGWaveSnapshot snap = c.snapshot();
    if (!snap.session) {
        return std::nullopt;
    }
    return snap.session->error;
}

std::optional<bg::BGWaveRoute> currentRoute(const bg::BGWaveController& c) {
    const bg::BGWaveSnapshot snap = c.snapshot();
    if (!snap.session) {
        return std::nullopt;
    }
    return snap.session->route;
}

std::optional<bool> currentSourceUnsupported(const bg::BGWaveController& c) {
    const bg::BGWaveSnapshot snap = c.snapshot();
    if (!snap.session) {
        return std::nullopt;
    }
    return snap.session->sourceUnsupported;
}

std::optional<bg::BGWaveInviteStatus> inviteStatus(const bg::BGWaveController& c, std::string_view sid) {
    const bg::BGWaveSnapshot snap = c.snapshot();
    for (const bg::BGWaveInviteEntry& entry : snap.invites) {
        if (entry.sidHex == sid) {
            return entry.invite.status;
        }
    }
    return std::nullopt;
}

std::size_t inviteCount(const bg::BGWaveController& c) {
    return c.snapshot().invites.size();
}

// A message from the peer of a private chat. The chat id is the peer's user id, so the sender defaults to it.
void receive(bg::BGWaveController& c,
             const std::string& uri,
             std::int64_t chat = 7,
             std::int64_t sender = 7,
             bool outgoing = false,
             bool privateChat = true,
             const std::string& account = "a",
             std::int64_t at = kNow) {
    c.onMessage(account, chat, sender, outgoing, privateChat, uri, at);
}

// ---- Golden control invites and invite fields (the BG-Media canonical codec) ----

void testControlInvitesMatchTheGoldenFixtures() {
    // The canonical fixtures carry exactly the fields a controller-made Cancel or End carries: default capabilities,
    // no candidates, and a 60 second lifetime from the issue time.
    CHECK(bg::encodeControlInvite(bw::WaveSignalType::Cancel, kSid, 1763000010, 3) == kCancelHttps);
    CHECK(bg::encodeControlInvite(bw::WaveSignalType::End, kSid, 1763000090, 4) == kEndHttps);
    CHECK(bg::encodeControlInvite(bw::WaveSignalType::Offer, kSid, 1763000010, 3).empty());
    CHECK(bg::encodeControlInvite(bw::WaveSignalType::Cancel, "zz", 1763000010, 3).empty());

    const std::optional<bg::BGWaveInviteFields> cancel = bg::decodeInviteFields(kCancelBg, 1763000010);
    CHECK(cancel.has_value());
    if (cancel) {
        CHECK(cancel->type == bw::WaveSignalType::Cancel);
        CHECK(cancel->sidHex == kSid);
        CHECK(cancel->nonce == 3);
        CHECK(cancel->expiresAt - cancel->issuedAt == bg::kInviteControlTtlSeconds);
    }
}

void testGoldenOfferFieldsAndExpiry() {
    const std::optional<bg::BGWaveInviteFields> offer = bg::decodeInviteFields(kOfferHttps, kFixtureNow);
    CHECK(offer.has_value());
    if (offer) {
        CHECK(offer->type == bw::WaveSignalType::Offer);
        CHECK(offer->sidHex == kSid);
        CHECK(offer->issuedAt == 1763000000);
        CHECK(offer->expiresAt == 1763000120);
        CHECK(offer->nonce == 1);
        CHECK(offer->candidateCount == 3);
        CHECK(offer->caps != 0);
    }
    std::string error;
    CHECK(!bg::decodeInviteFields(kOfferBg, kFixtureNow + 200, &error).has_value());
    CHECK(error == "invalid_or_expired");
}

void testSessionIdHexParsing() {
    std::array<std::uint8_t, 16> sid{};
    CHECK(bg::parseSessionIdHex(kSid, sid));
    CHECK(bw::formatSessionIdHex(sid) == kSid);
    CHECK(bg::parseSessionIdHex("FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF", sid));
    CHECK(bw::formatSessionIdHex(sid) == kOtherSid);
    CHECK(!bg::parseSessionIdHex("abc", sid));
    CHECK(!bg::parseSessionIdHex(std::string("zz") + std::string(30, '0'), sid));
}

// ---- Scenarios over the fake session (ported from BgWaveControllerTest.kt) ----

void testInvitationFromThePeerOfAPrivateChatIsRemembered() {
    Harness h;
    auto c = makeController(h);
    receive(*c, inviteLink(1));
    CHECK(inviteStatus(*c, kSid) == bg::BGWaveInviteStatus::Pending);
}

void testInvitationFromGroupWrongSenderOrOwnMessageIsIgnored() {
    Harness h;
    auto c = makeController(h);
    receive(*c, inviteLink(1), 7, 7, false, false);
    receive(*c, inviteLink(1), 7, 99);
    receive(*c, inviteLink(1), 7, 7, true);
    CHECK(inviteCount(*c) == 0);
}

void testExpiredOrDamagedInvitationIsIgnored() {
    Harness h;
    auto c = makeController(h);
    receive(*c, inviteLink(1, 1, kNow - 1));
    receive(*c, "bg://wave/v1/garbage");
    CHECK(inviteCount(*c) == 0);
}

void testReplayedInvitationDoesNotResetItsStatus() {
    Harness h;
    auto c = makeController(h);
    receive(*c, inviteLink(1));
    CHECK(c->decline(kSid, kNow).has_value());
    receive(*c, inviteLink(1));
    CHECK(inviteStatus(*c, kSid) == bg::BGWaveInviteStatus::Declined);
}

void testJoinSendsAnAnswerAndConnects() {
    Harness h;
    h.outbound = {inviteLink(2)};
    auto c = makeController(h);
    receive(*c, inviteLink(1));
    const std::optional<std::string> answer = c->join(kSid, kNow);
    CHECK(answer.has_value());
    CHECK(answer && answer->starts_with(bg::kInviteHttpsPrefix));
    CHECK(h.remote.size() == 1 && h.remote[0] == inviteLink(1));
    CHECK(currentPhase(*c) == bg::BGWavePhase::Connecting);
    CHECK(inviteStatus(*c, kSid) == bg::BGWaveInviteStatus::Joined);
}

void testJoinOfAnExpiredInvitationFails() {
    Harness h;
    auto c = makeController(h);
    receive(*c, inviteLink(1));
    CHECK(!c->join(kSid, kNow + 1000).has_value());
    CHECK(inviteStatus(*c, kSid) == bg::BGWaveInviteStatus::Expired);
    CHECK(currentError(*c) == bg::BGWaveError::Expired);
}

void testJoinWithoutNativeSupportReportsUnavailable() {
    Harness h;
    h.available = false;
    auto c = makeController(h);
    receive(*c, inviteLink(1));
    CHECK(!c->join(kSid, kNow).has_value());
    CHECK(currentError(*c) == bg::BGWaveError::Unavailable);
}

void testHostFlowOfferAnswerLive() {
    Harness h;
    h.outbound = {inviteLink(1)};
    auto c = makeController(h);
    CHECK(c->startHosting("a", 7, 7, kNow).has_value());
    CHECK(currentPhase(*c) == bg::BGWavePhase::Offering);
    c->offerSent(kSid, true, kNow);
    CHECK(currentPhase(*c) == bg::BGWavePhase::AwaitingAnswer);
    receive(*c, inviteLink(2));
    CHECK(currentPhase(*c) == bg::BGWavePhase::Connecting);
    h.nativeState = bw::WaveSessionState::LiveP2P;
    h.nativeRoute = bw::WaveTransportRoute::P2P;
    CHECK(c->poll(kNow).empty());
    CHECK(currentPhase(*c) == bg::BGWavePhase::Live);
    CHECK(currentRoute(*c) == bg::BGWaveRoute::Direct);
}

void testOversizedOfferIsReportedAsTooLargeNotRejected() {
    Harness h;
    const std::string huge = std::string(bg::kInviteUriPrefix) + "1-" + kSid + std::string(4096, 'a') + "-1-" +
                             std::to_string(kNow + 300);
    h.outbound = {huge};
    auto c = makeController(h);
    CHECK(!c->startHosting("a", 7, 7, kNow).has_value());
    CHECK(currentError(*c) == bg::BGWaveError::OfferTooLarge);
}

void testHostSourceUnsupportedFlagFollowsTheSessionAndIsHostOnly() {
    Harness h;
    h.outbound = {inviteLink(1)};
    auto c = makeController(h);
    static_cast<void>(c->startHosting("a", 7, 7, kNow));
    c->setHostSourceUnsupported(kSid, true);
    CHECK(currentSourceUnsupported(*c) == true);
    c->setHostSourceUnsupported(kOtherSid, false);
    CHECK(currentSourceUnsupported(*c) == true);
    c->setHostSourceUnsupported(kSid, false);
    CHECK(currentSourceUnsupported(*c) == false);
}

void testAnswerFromAnotherChatSenderAccountOrSessionIsIgnored() {
    for (int kase = 0; kase < 4; ++kase) {
        Harness h;
        h.outbound = {inviteLink(1)};
        auto c = makeController(h);
        static_cast<void>(c->startHosting("a", 7, 7, kNow));
        c->offerSent(kSid, true, kNow);
        switch (kase) {
        case 0:
            receive(*c, inviteLink(2), 8, 8);
            break;
        case 1:
            receive(*c, inviteLink(2), 7, 7, false, true, "b");
            break;
        case 2:
            receive(*c, inviteLink(2, 1, kNow + 300, kOtherSid));
            break;
        default:
            receive(*c, inviteLink(2), 7, 7, false, false);
            break;
        }
        CHECK(currentPhase(*c) == bg::BGWavePhase::AwaitingAnswer);
        CHECK(h.remote.empty());
    }
}

void testWrongAccountCannotPoisonTheAnswerReplayWindow() {
    Harness h;
    h.outbound = {inviteLink(1)};
    auto c = makeController(h);
    static_cast<void>(c->startHosting("a", 7, 7, kNow));
    c->offerSent(kSid, true, kNow);
    receive(*c, inviteLink(2, 99), 7, 7, false, true, "other");
    receive(*c, inviteLink(2, 1));
    CHECK(currentPhase(*c) == bg::BGWavePhase::Connecting);
    CHECK(h.remote.size() == 1 && h.remote[0] == inviteLink(2, 1));
}

void testAnswerCanArriveBeforeTelegramAcknowledgement() {
    Harness h;
    h.outbound = {inviteLink(1)};
    auto c = makeController(h);
    static_cast<void>(c->startHosting("a", 7, 7, kNow));
    receive(*c, inviteLink(2));
    c->offerSent(kSid, true, kNow);
    CHECK(currentPhase(*c) == bg::BGWavePhase::Connecting);
    CHECK(h.remote.size() == 1);
}

void testStopOfAFailedSessionClosesNativeAndClearsBusy() {
    Harness h;
    h.outbound = {inviteLink(1)};
    auto c = makeController(h);
    static_cast<void>(c->startHosting("a", 7, 7, kNow));
    c->offerSent(kSid, true, kNow);
    receive(*c, inviteLink(2));
    h.nativeState = bw::WaveSessionState::P2PFailed;
    static_cast<void>(c->poll(kNow));
    CHECK(currentPhase(*c) == bg::BGWavePhase::Failed);
    CHECK(currentError(*c) == bg::BGWaveError::NoConnection);
    CHECK(!c->stop(kNow).has_value());
    CHECK(h.destroyed == 1);
    CHECK(!c->snapshot().session.has_value());
}

void testResetOfAnotherAccountPreservesTheCurrentWave() {
    Harness h;
    h.outbound = {inviteLink(1)};
    auto c = makeController(h);
    static_cast<void>(c->startHosting("a", 7, 7, kNow));
    receive(*c, inviteLink(1, 1, kNow + 300, kOtherSid), 7, 7, false, true, "b");
    c->resetAccount("b", kNow);
    CHECK(c->snapshot().session && c->snapshot().session->accountId == "a");
    CHECK(inviteCount(*c) == 0);
    CHECK(h.destroyed == 0);
}

void testExpiredHostOfferReleasesTheNativeSession() {
    Harness h;
    h.outbound = {inviteLink(1)};
    auto c = makeController(h);
    static_cast<void>(c->startHosting("a", 7, 7, kNow));
    c->offerSent(kSid, true, kNow);
    static_cast<void>(c->poll(kNow + 301));
    CHECK(h.destroyed == 1);
    CHECK(currentPhase(*c) == bg::BGWavePhase::Ended);
}

void testRepeatedAnswerIsAReplay() {
    Harness h;
    h.outbound = {inviteLink(1)};
    auto c = makeController(h);
    static_cast<void>(c->startHosting("a", 7, 7, kNow));
    c->offerSent(kSid, true, kNow);
    receive(*c, inviteLink(2, 5));
    receive(*c, inviteLink(2, 5));
    receive(*c, inviteLink(2, 4));
    CHECK(h.remote.size() == 1);
}

void testFailedOfferSendClosesTheSession() {
    Harness h;
    h.outbound = {inviteLink(1)};
    auto c = makeController(h);
    static_cast<void>(c->startHosting("a", 7, 7, kNow));
    c->offerSent(kSid, false, kNow);
    CHECK(h.destroyed == 1);
    CHECK(currentError(*c) == bg::BGWaveError::SendFailed);
}

void testCancelFromThePeerEndsTheWaveAndAnEndedWaveIsNeverReopened() {
    Harness h;
    h.outbound = {inviteLink(1)};
    auto c = makeController(h);
    static_cast<void>(c->startHosting("a", 7, 7, kNow));
    c->offerSent(kSid, true, kNow);
    receive(*c, inviteLink(3));
    CHECK(currentPhase(*c) == bg::BGWavePhase::Ended);
    CHECK(h.destroyed == 1);
    receive(*c, inviteLink(1, 9));
    CHECK(!inviteStatus(*c, kSid).has_value());
}

void testCancelFromAStrangerDoesNotEndTheWave() {
    Harness h;
    h.outbound = {inviteLink(1)};
    auto c = makeController(h);
    static_cast<void>(c->startHosting("a", 7, 7, kNow));
    c->offerSent(kSid, true, kNow);
    receive(*c, inviteLink(3), 8, 8);
    CHECK(currentPhase(*c) == bg::BGWavePhase::AwaitingAnswer);
}

void testCancelOfAPendingInvitationMarksTheCard() {
    Harness h;
    auto c = makeController(h);
    receive(*c, inviteLink(1));
    receive(*c, inviteLink(3));
    CHECK(inviteStatus(*c, kSid) == bg::BGWaveInviteStatus::Cancelled);
}

void testUnknownSessionSignalsAreDropped() {
    Harness h;
    auto c = makeController(h);
    receive(*c, inviteLink(2));
    receive(*c, inviteLink(3));
    CHECK(inviteCount(*c) == 0);
    CHECK(!c->snapshot().session.has_value());
}

void testStopReturnsCancelBeforeAnswerAndEndAfter() {
    {
        Harness h;
        h.outbound = {inviteLink(1)};
        auto c = makeController(h);
        static_cast<void>(c->startHosting("a", 7, 7, kNow));
        c->offerSent(kSid, true, kNow);
        const std::optional<std::string> cancel = c->stop(kNow);
        CHECK(cancel.has_value());
        // Stop sends the Cancel with its own fixed nonce (2 for stop).
        CHECK(cancel && cancel->find(std::string("3-") + kSid + "-2-") != std::string::npos);
        CHECK(currentPhase(*c) == bg::BGWavePhase::Ended);
    }
    {
        Harness h;
        h.outbound = {inviteLink(1)};
        auto c = makeController(h);
        static_cast<void>(c->startHosting("a", 7, 7, kNow));
        c->offerSent(kSid, true, kNow);
        receive(*c, inviteLink(2));
        const std::optional<std::string> end = c->stop(kNow);
        CHECK(end.has_value());
        CHECK(end && end->find(std::string("4-") + kSid + "-2-") != std::string::npos);
        CHECK(h.destroyed == 1);
    }
}

void testCancelLinkUsesItsOwnNonce() {
    Harness h;
    auto c = makeController(h);
    const std::optional<std::string> cancel = c->cancelLink(kSid, kNow);
    CHECK(cancel.has_value());
    CHECK(cancel && cancel->find(std::string("3-") + kSid + "-3-") != std::string::npos);
    CHECK(!c->cancelLink("", kNow).has_value());
}

void testOnlyOneWaveAtATime() {
    Harness h;
    h.outbound = {inviteLink(1)};
    auto c = makeController(h);
    static_cast<void>(c->startHosting("a", 7, 7, kNow));
    CHECK(!c->startHosting("a", 8, 8, kNow).has_value());
    CHECK(currentPhase(*c) == bg::BGWavePhase::Offering);
    CHECK(currentError(*c) == bg::BGWaveError::None);
}

void testDeclineSendsCancelOnce() {
    Harness h;
    auto c = makeController(h);
    receive(*c, inviteLink(1));
    CHECK(c->decline(kSid, kNow).has_value());
    CHECK(!c->decline(kSid, kNow).has_value());
}

void testInviteTableIsBounded() {
    Harness h;
    h.available = false;
    auto c = makeController(h, 3);
    for (unsigned i = 0; i < 6; ++i) {
        char sid[33];
        std::snprintf(sid, sizeof sid, "%032x", i);
        receive(*c, inviteLink(1, 1, kNow + 300, sid));
    }
    CHECK(inviteCount(*c) == 3);
    CHECK(!inviteStatus(*c, "00000000000000000000000000000000").has_value());
}

void testNativeStatesMapToPhases() {
    using bgw = bg::BGWaveController;
    CHECK(bgw::phaseOf(bw::WaveSessionState::LiveP2P, bg::BGWavePhase::Connecting) == bg::BGWavePhase::Live);
    CHECK(bgw::phaseOf(bw::WaveSessionState::LiveTelegramCall, bg::BGWavePhase::Connecting) == bg::BGWavePhase::Live);
    CHECK(bgw::phaseOf(bw::WaveSessionState::ConnectingP2P, bg::BGWavePhase::Live) == bg::BGWavePhase::Connecting);
    CHECK(bgw::phaseOf(bw::WaveSessionState::P2PFailed, bg::BGWavePhase::Connecting) == bg::BGWavePhase::Failed);
    CHECK(bgw::phaseOf(bw::WaveSessionState::Ended, bg::BGWavePhase::Live) == bg::BGWavePhase::Ended);
    // States with no UI phase keep the fallback.
    CHECK(bgw::phaseOf(bw::WaveSessionState::Idle, bg::BGWavePhase::Reconnecting) == bg::BGWavePhase::Reconnecting);
    CHECK(bgw::phaseOf(bw::WaveSessionState::OfferingTelegramFallback, bg::BGWavePhase::Live) == bg::BGWavePhase::Live);
}

// ---- Behaviour the Android tests do not cover ----

void testOfferMessageGoneRetiresTheInviteAndTheHostOffer() {
    {
        Harness h;
        auto c = makeController(h);
        c->onMessage("a", 7, 7, false, true, inviteLink(1), kNow, 55);
        CHECK(c->hasOfferMessage("a", 7, 55));
        c->onOfferMessageGone("a", 7, 55, "", kNow);
        CHECK(inviteStatus(*c, kSid) == bg::BGWaveInviteStatus::Cancelled);
        CHECK(!c->hasOfferMessage("a", 7, 55));
    }
    {
        Harness h;
        h.outbound = {inviteLink(1)};
        auto c = makeController(h);
        static_cast<void>(c->startHosting("a", 7, 7, kNow));
        c->noteOfferMessage("a", 7, 77, kSid);
        c->onOfferMessageGone("a", 7, 77, "", kNow);
        CHECK(currentPhase(*c) == bg::BGWavePhase::Ended);
        CHECK(h.destroyed == 1);
    }
}

void testWillCloseListenerRunsBeforeTheSessionIsReleased() {
    Harness h;
    auto c = makeController(h);
    c->setSessionWillCloseListener([&h] { h.events.emplace_back("willClose"); });
    h.outbound = {inviteLink(1)};
    static_cast<void>(c->startHosting("a", 7, 7, kNow));
    c->offerSent(kSid, true, kNow);
    receive(*c, inviteLink(2));
    h.nativeState = bw::WaveSessionState::LiveP2P;
    static_cast<void>(c->poll(kNow));
    h.events.clear();
    static_cast<void>(c->stop(kNow));
    const std::vector<std::string> expected = {"willClose", "stop", "destroyed"};
    CHECK(h.events == expected);
}

void testChangesAreReportedToTheListener() {
    Harness h;
    auto c = makeController(h);
    int notifications = 0;
    c->setChangeListener([&notifications](const bg::BGWaveSnapshot&) { ++notifications; });
    receive(*c, inviteLink(1));
    CHECK(notifications >= 1);
}

// ---- Loopback over the real core (BGWaveSession, Pcm16WaveCodec and SimulatedWaveTransport) ----

std::unique_ptr<bg::BGWaveController> makeCoreController(std::shared_ptr<bw::SimulatedWaveTransport> transport,
                                                         bw::WaveRole role) {
    bg::BGWaveSession::Options options;
    options.role = role;
    return std::make_unique<bg::BGWaveController>(
        [options, transport](bool) -> std::unique_ptr<bg::BGWaveNativeSession> {
            return bg::makeBGWaveCoreSession(options, std::make_shared<bw::Pcm16WaveCodec>(), transport);
        });
}

void testControllersRunAWaveOverCoreSessions() {
    auto hostTransport = std::make_shared<bw::SimulatedWaveTransport>();
    auto listenerTransport = std::make_shared<bw::SimulatedWaveTransport>();
    bw::SimulatedWaveTransport::linkPeers(*hostTransport, *listenerTransport);
    auto host = makeCoreController(hostTransport, bw::WaveRole::Host);
    auto listener = makeCoreController(listenerTransport, bw::WaveRole::Listener);

    // The host's peer is the listener (user 22); the listener's peer is the host (user 11).
    const std::optional<std::string> offer = host->startHosting("a", 22, 22, kT0);
    CHECK(offer.has_value());
    if (!offer) {
        return;
    }
    CHECK(currentPhase(*host) == bg::BGWavePhase::Offering);
    const std::string sid = host->snapshot().session->sidHex;
    CHECK(sid.size() == 32);
    host->offerSent(sid, true, kT0);
    CHECK(currentPhase(*host) == bg::BGWavePhase::AwaitingAnswer);

    listener->onMessage("b", 11, 11, false, true, *offer, kT0 + 1);
    CHECK(inviteStatus(*listener, sid) == bg::BGWaveInviteStatus::Pending);
    const std::optional<std::string> answer = listener->join(sid, kT0 + 1);
    CHECK(answer.has_value());
    CHECK(currentPhase(*listener) == bg::BGWavePhase::Connecting);
    if (!answer) {
        return;
    }
    host->onMessage("a", 22, 22, false, true, *answer, kT0 + 2);
    CHECK(currentPhase(*host) == bg::BGWavePhase::Connecting);

    // Four seconds of simulated time in 10 ms steps, pumping both sides as the owner's timer does.
    double monotonic = 1000.0;
    for (int tick = 0; tick < 400; ++tick, monotonic += 0.01) {
        host->pump(monotonic);
        listener->pump(monotonic);
    }
    CHECK(host->poll(kT0 + 3).empty());
    CHECK(listener->poll(kT0 + 3).empty());
    CHECK(currentPhase(*host) == bg::BGWavePhase::Live);
    CHECK(currentPhase(*listener) == bg::BGWavePhase::Live);
    CHECK(currentRoute(*host) == bg::BGWaveRoute::Direct);

    // Stopping on the host sends an End. The listener accepts it once, and a second copy is a replay.
    const std::optional<std::string> end = host->stop(kT0 + 4);
    CHECK(end.has_value());
    CHECK(currentPhase(*host) == bg::BGWavePhase::Ended);
    if (!end) {
        return;
    }
    listener->onMessage("b", 11, 11, false, true, *end, kT0 + 4);
    CHECK(currentPhase(*listener) == bg::BGWavePhase::Ended);
    CHECK(inviteStatus(*listener, sid) == bg::BGWaveInviteStatus::Ended);
    listener->onMessage("b", 11, 11, false, true, *end, kT0 + 4);
    CHECK(currentPhase(*listener) == bg::BGWavePhase::Ended);
}

void testDeclineFromTheListenerEndsTheHostOffer() {
    auto hostTransport = std::make_shared<bw::SimulatedWaveTransport>();
    auto listenerTransport = std::make_shared<bw::SimulatedWaveTransport>();
    bw::SimulatedWaveTransport::linkPeers(*hostTransport, *listenerTransport);
    auto host = makeCoreController(hostTransport, bw::WaveRole::Host);
    auto listener = makeCoreController(listenerTransport, bw::WaveRole::Listener);

    const std::optional<std::string> offer = host->startHosting("a", 22, 22, kT0);
    CHECK(offer.has_value());
    if (!offer) {
        return;
    }
    const std::string sid = host->snapshot().session->sidHex;
    host->offerSent(sid, true, kT0);
    listener->onMessage("b", 11, 11, false, true, *offer, kT0 + 1);
    const std::optional<std::string> cancel = listener->decline(sid, kT0 + 1);
    CHECK(cancel.has_value());
    if (!cancel) {
        return;
    }
    CHECK(inviteStatus(*listener, sid) == bg::BGWaveInviteStatus::Declined);
    host->onMessage("a", 22, 22, false, true, *cancel, kT0 + 2);
    CHECK(currentPhase(*host) == bg::BGWavePhase::Ended);
}

}  // namespace

int main() {
    testControlInvitesMatchTheGoldenFixtures();
    testGoldenOfferFieldsAndExpiry();
    testSessionIdHexParsing();
    testInvitationFromThePeerOfAPrivateChatIsRemembered();
    testInvitationFromGroupWrongSenderOrOwnMessageIsIgnored();
    testExpiredOrDamagedInvitationIsIgnored();
    testReplayedInvitationDoesNotResetItsStatus();
    testJoinSendsAnAnswerAndConnects();
    testJoinOfAnExpiredInvitationFails();
    testJoinWithoutNativeSupportReportsUnavailable();
    testHostFlowOfferAnswerLive();
    testOversizedOfferIsReportedAsTooLargeNotRejected();
    testHostSourceUnsupportedFlagFollowsTheSessionAndIsHostOnly();
    testAnswerFromAnotherChatSenderAccountOrSessionIsIgnored();
    testWrongAccountCannotPoisonTheAnswerReplayWindow();
    testAnswerCanArriveBeforeTelegramAcknowledgement();
    testStopOfAFailedSessionClosesNativeAndClearsBusy();
    testResetOfAnotherAccountPreservesTheCurrentWave();
    testExpiredHostOfferReleasesTheNativeSession();
    testRepeatedAnswerIsAReplay();
    testFailedOfferSendClosesTheSession();
    testCancelFromThePeerEndsTheWaveAndAnEndedWaveIsNeverReopened();
    testCancelFromAStrangerDoesNotEndTheWave();
    testCancelOfAPendingInvitationMarksTheCard();
    testUnknownSessionSignalsAreDropped();
    testStopReturnsCancelBeforeAnswerAndEndAfter();
    testCancelLinkUsesItsOwnNonce();
    testOnlyOneWaveAtATime();
    testDeclineSendsCancelOnce();
    testInviteTableIsBounded();
    testNativeStatesMapToPhases();
    testOfferMessageGoneRetiresTheInviteAndTheHostOffer();
    testWillCloseListenerRunsBeforeTheSessionIsReleased();
    testChangesAreReportedToTheListener();
    testControllersRunAWaveOverCoreSessions();
    testDeclineFromTheListenerEndsTheHostOffer();
    if (gFailures != 0) {
        std::fprintf(stderr, "BGWaveControllerTests: %d check(s) failed\n", gFailures);
        return 1;
    }
    std::printf("BGWaveControllerTests: all checks passed\n");
    return 0;
}
