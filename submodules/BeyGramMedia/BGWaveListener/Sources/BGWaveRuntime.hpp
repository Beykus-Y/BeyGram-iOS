// BG Wave runtime for one session (stage 4 in docs/bg-wave-ios.md). It owns the Opus codec, the libdatachannel transport
// and BGWaveSession, so the Objective-C++ facade only forwards calls. Plain C++20: no ObjC and no UIKit.
#pragma once

#include "BGWavePcmTap.hpp"

#include "../../BGWaveCore/BGWaveSession.hpp"
#include "bgmedia/audio/IPcmOutputTap.hpp"
#include "bgmedia/wave/WaveTypes.hpp"
#include "bgmedia/wave/WebRtcWaveTransport.hpp"

#include <cstddef>
#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <string_view>

namespace beygram::wave {

// What a failed session most likely means. iOS reports a denied Local Network permission to no API: the connections
// just fail. So LocalNetworkSuspected is a suspicion, and the UI has to say "possibly".
enum class WaveFailureKind {
    None,
    LocalNetworkSuspected,
    Other,
};

// The decision behind WaveFailureKind, without the objects, so that a test can cover it. A failed P2P attempt that
// selected no candidate pair is the case worth explaining to the user.
[[nodiscard]] WaveFailureKind classifyWaveFailure(bgmedia::wave::WaveSessionState session,
                                                  bgmedia::wave::WaveTransportState transport,
                                                  bool hasSelectedCandidatePair) noexcept;

class BGWaveRuntime final {
public:
    struct Options {
        bgmedia::wave::WaveRole role = bgmedia::wave::WaveRole::Listener;
        std::uint32_t bitrateBps = bgmedia::wave::kWaveDefaultBitrateBps;
        std::int64_t offerTtlSeconds = 120;
    };

    explicit BGWaveRuntime(Options options);
    ~BGWaveRuntime();

    BGWaveRuntime(const BGWaveRuntime&) = delete;
    BGWaveRuntime& operator=(const BGWaveRuntime&) = delete;

    // Control calls: one thread at a time, never from the audio thread. A non-positive time means the wall clock.
    [[nodiscard]] bool startOffer(std::int64_t nowUnixSeconds);
    [[nodiscard]] bool acceptInvite(std::string_view link, std::int64_t nowUnixSeconds, std::string* error = nullptr);
    [[nodiscard]] std::optional<std::string> pollOutboundInvite();
    [[nodiscard]] bool reconnect(std::int64_t nowUnixSeconds);
    void stop(bool emitEnd, std::int64_t nowUnixSeconds);
    // Drives the pipeline. Call it every 10 to 20 ms from a worker thread.
    void process(double nowSeconds);

    // Real-time safe. The listener pulls decoded PCM, and the host pushes the mix.
    [[nodiscard]] std::size_t pullListenerPcm(float* outInterleavedStereo,
                                              std::size_t frames,
                                              std::uint32_t sampleRate) noexcept;
    void pushHostPcm(const float* interleavedStereo, std::size_t frames, std::uint32_t sampleRate) noexcept;
    // The host tap for the mix engine. It forwards to pushHostPcm. Attaching it to the engine is music-core work.
    [[nodiscard]] bgmedia::IPcmOutputTap& hostTap() noexcept { return tap_; }

    [[nodiscard]] bgmedia::wave::WaveSessionState state() const noexcept;
    // The transport route of the session, as the facade reports it (P2P or ExternalCall, or None before a route exists).
    [[nodiscard]] bgmedia::wave::WaveTransportRoute route() const noexcept;
    [[nodiscard]] WaveFailureKind failureKind() const;
    [[nodiscard]] std::string lastError() const;

private:
    static void forwardHostPcm(void* context,
                               const float* interleavedStereo,
                               std::size_t frames,
                               std::uint32_t sampleRate) noexcept;

    std::shared_ptr<bgmedia::wave::WebRtcWaveTransport> transport_;
    std::unique_ptr<BGWaveSession> session_;
    BGWavePcmTap tap_;
};

}  // namespace beygram::wave
