#pragma once

// Track preparation for BG Mix on iOS. Same steps as the desktop loader in BG-Media
// (prepareMixTrack in adapters/miniaudio/src/MiniaudioMixLoader.cpp, on the pinned dev core),
// but decoding is injected so the iOS layer can use AVAudioFile instead of miniaudio.
//
// Every stage passes through a checkpoint. The checkpoint calls the progress callback, and the
// MixSession callback behind it throws once the job is cancelled, so removing a track or
// destroying the session stops the work between chunks instead of after the whole analysis.

#include "BGMediaPcmLimits.hpp"

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
    // Largest decoded source and mixer buffer, in bytes. Longer tracks are refused before analysis.
    std::uint64_t maxPcmBytes = kMixMaxTrackPcmBytes;
};

// Returns normally when the job may continue. Throws to abort (MixSession throws when the job was cancelled).
using MixCheckpoint = std::function<void()>;

// Fills `out` with interleaved float PCM. Must return false with `error` set, before allocating,
// when the decoded size would exceed `maxDecodedBytes`. Must call `checkpoint` between chunks and
// let its exception propagate after releasing platform objects.
using MixDecodeFunction = std::function<bool(
    const std::filesystem::path& path, std::uint64_t maxDecodedBytes,
    const MixCheckpoint& checkpoint, bgmedia::AudioData& out, std::string& error)>;

using MixPreparationProgress =
    std::function<void(float fraction, std::string_view stage)>;

bool prepareMixTrack(const std::filesystem::path& path,
                     const MixDecodeFunction& decode,
                     const MixPreparationOptions& options,
                     bgmedia::mix::PreparedMixTrack& out, std::string& error,
                     const MixPreparationProgress& progress = {});

} // namespace beygram::media
