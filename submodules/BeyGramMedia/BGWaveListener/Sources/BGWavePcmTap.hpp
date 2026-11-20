// Host side of BG Wave (stage 2 in docs/bg-wave-ios.md). The mix engine calls IPcmOutputTap from its real-time render
// thread. This adapter forwards each call to a plain C sink, without allocation, locks or exceptions. The caller that
// owns the session chooses the sink (BGWaveListenerSession, stage 4) and decides what happens to the frames.
#pragma once

#include "bgmedia/audio/IPcmOutputTap.hpp"

#include <cstddef>
#include <cstdint>

namespace beygram::wave {

class BGWavePcmTap final : public bgmedia::IPcmOutputTap {
public:
    // Real-time safe: called on the audio render thread. The sink must not lock, allocate or throw.
    using Sink = void (*)(void* context,
                          const float* interleavedStereo,
                          std::size_t frames,
                          std::uint32_t sampleRate) noexcept;

    // `context` is passed back to `sink` unchanged. A null sink makes the tap a no-op.
    BGWavePcmTap(Sink sink, void* context) noexcept : sink_(sink), context_(context) {}

    void onPcmRendered(const float* interleavedStereo,
                       std::size_t frames,
                       std::uint32_t sampleRate) noexcept override {
        if (sink_ != nullptr) {
            sink_(context_, interleavedStereo, frames, sampleRate);
        }
    }

private:
    Sink sink_;
    void* context_;
};

}  // namespace beygram::wave
