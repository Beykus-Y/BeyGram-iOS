#pragma once

// Track preparation for BG Mix on iOS. Same pipeline as BG-Media's desktop
// loader (prepareMixTrack in adapters/miniaudio), but decoding is injected so
// the iOS layer can use AVAudioFile instead of miniaudio.

#include "bgmedia/analysis/AnalysisConfig.hpp"
#include "bgmedia/audio/AudioData.hpp"
#include "bgmedia/mix/MixFeatureMap.hpp"
#include "bgmedia/mix/MixSession.hpp"

#include <cstdint>
#include <filesystem>
#include <functional>
#include <string>
#include <string_view>

namespace beygram::media {

struct MixPreparationOptions {
    std::filesystem::path cacheDirectory;
    bgmedia::AnalysisConfig analysis;
    bgmedia::mix::MixFeatureConfig features;
    bool useCache = true;
    std::uint32_t targetSampleRate = 48000;
};

// Fills `out` with interleaved float PCM. Returns false with `error` set.
using MixDecodeFunction = std::function<bool(
    const std::filesystem::path& path, bgmedia::AudioData& out,
    std::string& error)>;

using MixPreparationProgress =
    std::function<void(float fraction, std::string_view stage)>;

bool prepareMixTrack(const std::filesystem::path& path,
                     const MixDecodeFunction& decode,
                     const MixPreparationOptions& options,
                     bgmedia::mix::PreparedMixTrack& out, std::string& error,
                     const MixPreparationProgress& progress = {});

} // namespace beygram::media
