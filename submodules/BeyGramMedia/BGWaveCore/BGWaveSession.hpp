// BG Wave session for iOS: one Host or Listener session over the BG-Media pipeline (WaveAudioPipeline).
// It does not depend on a transport or a codec. The caller injects both: production uses Opus and a real P2P transport
// (later stages, see docs/bg-wave-ios.md); tests use Pcm16WaveCodec and SimulatedWaveTransport.
#pragma once

#include "bgmedia/wave/WaveAudioPipeline.hpp"
#include "bgmedia/wave/WaveCodec.hpp"
#include "bgmedia/wave/WaveSignaling.hpp"
#include "bgmedia/wave/WaveTransport.hpp"
#include "bgmedia/wave/WaveTypes.hpp"

#include <cstddef>
#include <cstdint>
#include <deque>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <string_view>

namespace beygram::wave {

class BGWaveSession final {
public:
    struct Options {
        bgmedia::wave::WaveRole role = bgmedia::wave::WaveRole::Host;
        std::uint32_t bitrateBps = bgmedia::wave::kWaveDefaultBitrateBps;
        // How long a new Offer stays valid, in seconds. BG-Media caps signal lifetimes at 600 seconds.
        std::int64_t offerTtlSeconds = 120;
    };

    // `codec` and `transport` must be non-null. Otherwise every call fails and lastError() says why.
    BGWaveSession(Options options,
                  std::shared_ptr<bgmedia::wave::IWaveAudioCodec> codec,
                  std::shared_ptr<bgmedia::wave::IWaveTransport> transport);
    ~BGWaveSession();

    BGWaveSession(const BGWaveSession&) = delete;
    BGWaveSession& operator=(const BGWaveSession&) = delete;

    // Host only: starts the session and queues its Offer invite (see pollOutboundInvite).
    [[nodiscard]] bool startOffer(std::int64_t nowUnixSeconds);

    // Routes one invite from the peer: Offer, Answer, Cancel or End, in either link form. A Listener accepts an Offer
    // and queues its Answer. A Host accepts an Answer. Cancel and End end the session.
    [[nodiscard]] bool acceptInvite(std::string_view link, std::int64_t nowUnixSeconds, std::string* error = nullptr);

    // The next invite to send, in the Telegram-safe https form, or nothing when the queue is empty.
    [[nodiscard]] std::optional<std::string> pollOutboundInvite();

    // Starts a new offer after P2PFailed. Returns false when the current state does not allow it.
    [[nodiscard]] bool reconnect(std::int64_t nowUnixSeconds);

    // Ends the session. With emitEnd the peer's End invite is queued (see pollOutboundInvite).
    void stop(bool emitEnd, std::int64_t nowUnixSeconds);

    // Drives the pipeline. Call every 10-20 ms from a worker thread, never from the real-time audio thread.
    void process(double nowSeconds);

    // Host: interleaved stereo float PCM from the mix at any sample rate. Real-time safe.
    void pushHostPcm(const float* interleavedStereo, std::size_t frames, std::uint32_t sampleRate) noexcept;

    // Listener: fills `outInterleavedStereo` with decoded audio and returns the number of frames written. Real-time safe.
    [[nodiscard]] std::size_t pullListenerPcm(float* outInterleavedStereo,
                                              std::size_t frames,
                                              std::uint32_t sampleRate) noexcept;

    [[nodiscard]] bgmedia::wave::WaveSessionState state() const noexcept;
    [[nodiscard]] bgmedia::wave::WaveTransportRoute route() const noexcept;
    [[nodiscard]] bgmedia::wave::WaveStats stats() const;
    // Redacted summary from the pipeline, safe for logs.
    [[nodiscard]] std::string diagnosticsSummary() const;
    // The last failure as a fixed code name (for example "encode_failed"). Empty when there was none.
    [[nodiscard]] std::string lastError() const;

private:
    void queueOutbound(const bgmedia::wave::WaveSignalMessage& message);
    void recordError(bgmedia::wave::WaveErrorCode code);

    Options options_;
    // Guards outbound_ and lastError_. Declared before pipeline_, so it outlives the pipeline's callbacks.
    mutable std::mutex mutex_;
    std::deque<std::string> outbound_;
    std::string lastError_;
    std::shared_ptr<bgmedia::wave::WaveAudioPipeline> pipeline_;
};

}  // namespace beygram::wave
