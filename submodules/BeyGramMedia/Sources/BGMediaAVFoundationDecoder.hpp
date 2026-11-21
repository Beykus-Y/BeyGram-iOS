#pragma once

#include "BGMediaMixPreparation.hpp"

#include "bgmedia/audio/AudioData.hpp"

#include <cstdint>
#include <filesystem>
#include <string>

namespace beygram::media {

// Decodes an audio file using AVFoundation (AVAudioFile primary, AVAssetReader fallback for
// containers ExtAudioFile cannot read) into interleaved float32 PCM.
//
// Enforces `maxDecodedBytes` before allocating full-length buffers and invokes `checkpoint`
// between chunks so cancelled preparation jobs abort promptly without leaking Objective-C objects.
// On failure, `error` receives a redacted diagnostic (extension, byte size, leading 4-byte hex,
// error domain/code) without ever including file paths, URLs, or credentials.
bool decodeWithAVFoundation(const std::filesystem::path& path,
                            std::uint64_t maxDecodedBytes,
                            const MixCheckpoint& checkpoint,
                            bgmedia::AudioData& out,
                            std::string& error);

// Redacted file metadata string (`ext=... bytes=... head=...`), safe for logs and UI diagnostics.
std::string redactedAudioFileSummary(const std::filesystem::path& path);

} // namespace beygram::media
