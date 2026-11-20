#include "BGWaveSession.hpp"

#include "BGWaveInvite.hpp"

#include <utility>

namespace beygram::wave {
namespace bw = bgmedia::wave;
namespace {

// Fixed code names. Core error messages can carry protocol details, so only the code is kept.
const char* errorCodeName(bw::WaveErrorCode code) {
    switch (code) {
    case bw::WaveErrorCode::None:
        return "none";
    case bw::WaveErrorCode::InvalidState:
        return "invalid_state";
    case bw::WaveErrorCode::InvalidArgument:
        return "invalid_argument";
    case bw::WaveErrorCode::SignalingFailed:
        return "signaling_failed";
    case bw::WaveErrorCode::TransportFailed:
        return "transport_failed";
    case bw::WaveErrorCode::CodecFailed:
        return "codec_failed";
    case bw::WaveErrorCode::FallbackFailed:
        return "fallback_failed";
    case bw::WaveErrorCode::PublishingRevoked:
        return "publishing_revoked";
    }
    return "unknown";
}

void setError(std::string* error, const char* reason) {
    if (error != nullptr) {
        *error = reason;
    }
}

}  // namespace

BGWaveSession::BGWaveSession(Options options,
                             std::shared_ptr<bw::IWaveAudioCodec> codec,
                             std::shared_ptr<bw::IWaveTransport> transport)
    : options_(options) {
    if (!codec || !transport) {
        lastError_ = "missing_codec_or_transport";
        return;
    }
    bw::WavePipelineConfig config;
    config.role = options_.role;
    config.targetBitrateBps = options_.bitrateBps;
    config.defaultOfferTtlSeconds = options_.offerTtlSeconds;
    pipeline_ = std::make_shared<bw::WaveAudioPipeline>(config, std::move(codec), std::move(transport));

    bw::WavePipelineCallbacks callbacks;
    callbacks.onOutboundSignal = [this](const bw::WaveSignalMessage& message) { queueOutbound(message); };
    callbacks.onError = [this](const bw::WaveError& error) { recordError(error.code); };
    pipeline_->setCallbacks(std::move(callbacks));
}

BGWaveSession::~BGWaveSession() {
    // Detach the callbacks first, so the pipeline never calls back into a session that is being destroyed.
    if (pipeline_) {
        pipeline_->setCallbacks(bw::WavePipelineCallbacks{});
    }
}

bool BGWaveSession::startOffer(std::int64_t nowUnixSeconds) {
    return startOffer(nowUnixSeconds, options_.offerTtlSeconds);
}

bool BGWaveSession::startOffer(std::int64_t nowUnixSeconds, std::int64_t offerTtlSeconds) {
    if (!pipeline_ || options_.role != bw::WaveRole::Host) {
        return false;
    }
    if (offerTtlSeconds <= 0 || offerTtlSeconds > bw::kWaveMaxSignalTtlSeconds) {
        return false;
    }
    return pipeline_->startOffer(resolveUnixSeconds(nowUnixSeconds), offerTtlSeconds);
}

bool BGWaveSession::acceptInvite(std::string_view link, std::int64_t nowUnixSeconds, std::string* error) {
    if (!pipeline_) {
        setError(error, "unavailable");
        return false;
    }
    const std::int64_t now = resolveUnixSeconds(nowUnixSeconds);
    bw::WaveSignalMessage message;
    if (!decodeInvite(link, now, message, error)) {
        return false;
    }
    if (!pipeline_->handleRemoteSignal(message, now)) {
        setError(error, "rejected");
        return false;
    }
    return true;
}

std::optional<std::string> BGWaveSession::pollOutboundInvite() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (outbound_.empty()) {
        return std::nullopt;
    }
    std::string next = std::move(outbound_.front());
    outbound_.pop_front();
    return next;
}

bool BGWaveSession::reconnect(std::int64_t nowUnixSeconds) {
    return pipeline_ && pipeline_->reconnect(resolveUnixSeconds(nowUnixSeconds));
}

void BGWaveSession::stop(bool emitEnd, std::int64_t nowUnixSeconds) {
    if (pipeline_) {
        pipeline_->stop(emitEnd, resolveUnixSeconds(nowUnixSeconds));
    }
}

void BGWaveSession::process(double nowSeconds) {
    if (pipeline_) {
        pipeline_->process(nowSeconds);
    }
}

void BGWaveSession::pushHostPcm(const float* interleavedStereo, std::size_t frames, std::uint32_t sampleRate) noexcept {
    if (pipeline_) {
        pipeline_->pushHostPcm(interleavedStereo, frames, sampleRate);
    }
}

std::size_t BGWaveSession::pullListenerPcm(float* outInterleavedStereo,
                                           std::size_t frames,
                                           std::uint32_t sampleRate) noexcept {
    return pipeline_ ? pipeline_->pullListenerPcm(outInterleavedStereo, frames, sampleRate) : 0;
}

bw::WaveSessionState BGWaveSession::state() const noexcept {
    return pipeline_ ? pipeline_->state() : bw::WaveSessionState::Failed;
}

bw::WaveTransportRoute BGWaveSession::route() const noexcept {
    return pipeline_ ? pipeline_->route() : bw::WaveTransportRoute::None;
}

bw::WaveStats BGWaveSession::stats() const {
    return pipeline_ ? pipeline_->stats() : bw::WaveStats{};
}

std::string BGWaveSession::diagnosticsSummary() const {
    return pipeline_ ? pipeline_->diagnosticsSummary() : std::string("unavailable");
}

std::string BGWaveSession::lastError() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return lastError_;
}

void BGWaveSession::queueOutbound(const bw::WaveSignalMessage& message) {
    std::string encodeError;
    std::string invite = encodeInvite(message, &encodeError);
    std::lock_guard<std::mutex> lock(mutex_);
    if (invite.empty()) {
        lastError_ = encodeError;
        return;
    }
    outbound_.push_back(std::move(invite));
}

void BGWaveSession::recordError(bw::WaveErrorCode code) {
    std::lock_guard<std::mutex> lock(mutex_);
    lastError_ = errorCodeName(code);
}

}  // namespace beygram::wave
