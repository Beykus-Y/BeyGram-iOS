#pragma once

// In-memory PCM limits for BG Mix on iOS. Pure C++ with no Apple types, so the host tests in
// Tests/BGMediaPcmLimitsTests.cpp run anywhere. The numbers match the Android bridge
// (app/src/main/cpp/bgmix_jni.cpp): 128 MiB per track, 272 MiB for preparation, 400 MiB per session.

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <stdexcept>
#include <utility>
#include <vector>

namespace beygram::media {

inline constexpr std::uint64_t kMixMiB = 1024ull * 1024ull;
inline constexpr std::uint64_t kMixMaxTrackPcmBytes = 128 * kMixMiB;
inline constexpr std::uint64_t kMixPreparationPcmReserve = 272 * kMixMiB;
inline constexpr std::uint64_t kMixSessionPcmBudget = kMixMaxTrackPcmBytes + kMixPreparationPcmReserve;

// Bytes of interleaved float32 PCM for `frames` frames of `channels` channels. Saturates instead of overflowing.
[[nodiscard]] inline std::uint64_t interleavedFloatBytes(std::uint64_t frames, std::uint32_t channels) noexcept {
    const std::uint64_t perFrame = static_cast<std::uint64_t>(channels) * sizeof(float);
    if (perFrame != 0 && frames > std::numeric_limits<std::uint64_t>::max() / perFrame) {
        return std::numeric_limits<std::uint64_t>::max();
    }
    return frames * perFrame;
}

// Whether a source of `sourceFrames` at `sourceRate` fits the mixer's in-memory limit after it is resampled to
// `targetRate` (0 keeps the source rate) and folded to at most two channels. This is the same rule as the desktop
// loader, adapters/miniaudio/src/MiniaudioMixLoader.cpp in BG-Media.
[[nodiscard]] inline bool mixerPcmFits(std::uint64_t sourceFrames, std::uint32_t sourceRate,
                                       std::uint32_t targetRate, std::uint32_t channels,
                                       std::uint64_t maxPcmBytes) noexcept {
    if (sourceRate == 0 || channels == 0) {
        return false;
    }
    const std::uint32_t rate = targetRate == 0 ? sourceRate : targetRate;
    const std::uint32_t mixChannels = std::min<std::uint32_t>(channels, 2u);
    const std::uint64_t maxFrames = maxPcmBytes / sizeof(float) / mixChannels;
    if (maxFrames == 0) {
        return false;
    }
    const long double estimatedFrames =
        static_cast<long double>(sourceFrames) * rate / sourceRate;
    return !(estimatedFrames + 0.5L >= static_cast<long double>(maxFrames) + 1.0L);
}

// Interleaves planar float blocks into storage reserved once for the expected length, so a decode never holds a
// second full-length copy of the source. Throws std::length_error when the result would exceed `maxPcmBytes`, and
// std::invalid_argument for a layout without channels.
class InterleavedPcmBuilder {
public:
    InterleavedPcmBuilder(std::uint32_t channels, std::uint64_t expectedFrames, std::uint64_t maxPcmBytes)
        : channels_(channels) {
        if (channels_ == 0) {
            throw std::invalid_argument("PCM needs at least one channel");
        }
        if (interleavedFloatBytes(expectedFrames, channels_) > maxPcmBytes) {
            throw std::length_error("decoded PCM exceeds the in-memory limit");
        }
        maxFrames_ = maxPcmBytes / sizeof(float) / channels_;
        samples_.reserve(static_cast<std::size_t>(expectedFrames * channels_));
    }

    // `planes[c]` points at `frames` samples of channel c.
    void appendPlanar(const float* const* planes, std::size_t frames) {
        if (frames > maxFrames_ - frames_) {
            throw std::length_error("decoded PCM exceeds the in-memory limit");
        }
        const std::size_t base = samples_.size();
        samples_.resize(base + frames * channels_);
        float* dst = samples_.data() + base;
        for (std::uint32_t c = 0; c < channels_; ++c) {
            const float* src = planes[c];
            for (std::size_t i = 0; i < frames; ++i) {
                dst[i * channels_ + c] = src[i];
            }
        }
        frames_ += frames;
    }

    [[nodiscard]] std::size_t frames() const noexcept { return frames_; }

    // Hands over the interleaved samples. The builder is empty afterwards.
    [[nodiscard]] std::vector<float> take() noexcept {
        frames_ = 0;
        return std::exchange(samples_, {});
    }

private:
    std::uint32_t channels_ = 0;
    std::uint64_t maxFrames_ = 0;
    std::size_t frames_ = 0;
    std::vector<float> samples_;
};

} // namespace beygram::media
