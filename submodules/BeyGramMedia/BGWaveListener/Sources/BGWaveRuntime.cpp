#include "BGWaveRuntime.hpp"

#include "bgmedia/wave/OpusWaveCodec.hpp"

namespace beygram::wave {

namespace bw = bgmedia::wave;

WaveFailureKind classifyWaveFailure(bw::WaveSessionState session,
                                    bw::WaveTransportState transport,
                                    bool hasSelectedCandidatePair) noexcept {
    const bool sessionFailed = session == bw::WaveSessionState::P2PFailed || session == bw::WaveSessionState::Failed;
    if (!sessionFailed) {
        return WaveFailureKind::None;
    }
    if (transport == bw::WaveTransportState::Failed && !hasSelectedCandidatePair) {
        return WaveFailureKind::LocalNetworkSuspected;
    }
    return WaveFailureKind::Other;
}

BGWaveRuntime::BGWaveRuntime(Options options)
    : transport_(),
      session_(),
      tap_(&BGWaveRuntime::forwardHostPcm, this) {
    bw::WebRtcTransportConfig transportConfig;
    transportConfig.role = options.role;
    transport_ = std::make_shared<bw::WebRtcWaveTransport>(transportConfig);

    BGWaveSession::Options sessionOptions;
    sessionOptions.role = options.role;
    sessionOptions.bitrateBps = options.bitrateBps;
    sessionOptions.offerTtlSeconds = options.offerTtlSeconds;
    auto codec = std::make_shared<bw::OpusWaveCodec>(options.bitrateBps);
    session_ = std::make_unique<BGWaveSession>(sessionOptions, codec, transport_);
}

BGWaveRuntime::~BGWaveRuntime() {
    if (session_) {
        session_->stop(false, 0);
    }
}

bool BGWaveRuntime::startOffer(std::int64_t nowUnixSeconds) {
    return session_->startOffer(nowUnixSeconds);
}

bool BGWaveRuntime::acceptInvite(std::string_view link, std::int64_t nowUnixSeconds, std::string* error) {
    return session_->acceptInvite(link, nowUnixSeconds, error);
}

std::optional<std::string> BGWaveRuntime::pollOutboundInvite() {
    return session_->pollOutboundInvite();
}

bool BGWaveRuntime::reconnect(std::int64_t nowUnixSeconds) {
    return session_->reconnect(nowUnixSeconds);
}

void BGWaveRuntime::stop(bool emitEnd, std::int64_t nowUnixSeconds) {
    session_->stop(emitEnd, nowUnixSeconds);
}

void BGWaveRuntime::process(double nowSeconds) {
    session_->process(nowSeconds);
}

std::size_t BGWaveRuntime::pullListenerPcm(float* outInterleavedStereo,
                                           std::size_t frames,
                                           std::uint32_t sampleRate) noexcept {
    return session_->pullListenerPcm(outInterleavedStereo, frames, sampleRate);
}

void BGWaveRuntime::pushHostPcm(const float* interleavedStereo, std::size_t frames, std::uint32_t sampleRate) noexcept {
    session_->pushHostPcm(interleavedStereo, frames, sampleRate);
}

bw::WaveSessionState BGWaveRuntime::state() const noexcept {
    return session_->state();
}

WaveFailureKind BGWaveRuntime::failureKind() const {
    return classifyWaveFailure(session_->state(),
                               transport_->state(),
                               !transport_->selectedCandidatePairSummary().empty());
}

std::string BGWaveRuntime::lastError() const {
    return session_->lastError();
}

void BGWaveRuntime::forwardHostPcm(void* context,
                                   const float* interleavedStereo,
                                   std::size_t frames,
                                   std::uint32_t sampleRate) noexcept {
    static_cast<BGWaveRuntime*>(context)->pushHostPcm(interleavedStereo, frames, sampleRate);
}

}  // namespace beygram::wave
