#import "BGMediaAVFoundationDecoder.hpp"

#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <stdexcept>
#include <vector>

namespace beygram::media {

namespace {

constexpr AVAudioFrameCount kAVAudioFileChunkFrames = 65536;

std::string sanitizedExtension(const std::filesystem::path& path) {
    std::string ext = path.extension().string();
    if (!ext.empty() && ext.front() == '.') {
        ext.erase(ext.begin());
    }
    std::string clean;
    clean.reserve(std::min<std::size_t>(ext.size(), 8));
    for (unsigned char ch : ext) {
        if (std::isalnum(ch) && clean.size() < 8) {
            clean.push_back(static_cast<char>(std::tolower(ch)));
        }
    }
    return clean.empty() ? "none" : clean;
}

std::string redactedNSError(NSError *error) {
    if (error == nil) {
        return "none";
    }
    const char *domain = error.domain.UTF8String;
    char buf[160];
    std::snprintf(buf, sizeof(buf), "%s:%ld", domain ? domain : "unknown", (long)error.code);
    return std::string(buf);
}

struct SampleBufferGuard {
    CMSampleBufferRef ref = nullptr;
    ~SampleBufferGuard() {
        if (ref != nullptr) {
            CFRelease(ref);
        }
    }
};

bool decodeWithAVAudioFile(const std::filesystem::path& path,
                           std::uint64_t maxDecodedBytes,
                           const MixCheckpoint& checkpoint,
                           bgmedia::AudioData& out,
                           bool& hitPcmLimit,
                           std::string& detailError) {
    AVAudioFile *file = nil;
    AVAudioPCMBuffer *buffer = nil;
    try {
        @autoreleasepool {
            NSString *filePath = [NSString stringWithUTF8String:path.c_str()];
            if (filePath == nil) {
                detailError = "invalid_path";
                return false;
            }
            NSError *nsError = nil;
            file = [[AVAudioFile alloc] initForReading:[NSURL fileURLWithPath:filePath] error:&nsError];
            if (file == nil) {
                detailError = "open:" + redactedNSError(nsError);
                return false;
            }
            AVAudioFormat *format = file.processingFormat; // float32, non-interleaved
            const AVAudioFramePosition length = file.length;
            if (length <= 0 || format.channelCount == 0 || format.sampleRate <= 0.0) {
                detailError = "empty_header";
                return false;
            }
            const auto channels = static_cast<std::uint32_t>(format.channelCount);
            if (interleavedFloatBytes(static_cast<std::uint64_t>(length), channels) > maxDecodedBytes) {
                hitPcmLimit = true;
                detailError = "pcm_limit";
                return false;
            }
            buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:kAVAudioFileChunkFrames];
            if (buffer == nil) {
                detailError = "buffer_alloc";
                return false;
            }
            InterleavedPcmBuilder builder(channels, static_cast<std::uint64_t>(length), maxDecodedBytes);
            for (;;) {
                nsError = nil;
                buffer.frameLength = 0;
                const BOOL ok = [file readIntoBuffer:buffer frameCount:kAVAudioFileChunkFrames error:&nsError];
                const AVAudioFrameCount frames = buffer.frameLength;
                if (!ok) {
                    // Apple's AVAudioFile returns NO with nsError == nil and frameLength == 0
                    // once reading reaches normal end-of-file.
                    if (nsError == nil && frames == 0 && builder.frames() > 0) {
                        break;
                    }
                    detailError = "read:" + redactedNSError(nsError);
                    return false;
                }
                if (frames == 0) {
                    break;
                }
                if (buffer.floatChannelData == nullptr) {
                    detailError = "no_float_planes";
                    return false;
                }
                try {
                    builder.appendPlanar(buffer.floatChannelData, frames);
                } catch (const std::length_error&) {
                    hitPcmLimit = true;
                    detailError = "pcm_limit";
                    return false;
                }
                checkpoint();
            }
            if (builder.frames() == 0) {
                detailError = "empty_samples";
                return false;
            }
            out.channels = channels;
            out.sampleRate = static_cast<std::uint32_t>(format.sampleRate);
            out.samples = builder.take();
            return out.valid();
        }
    } catch (...) {
        buffer = nil;
        file = nil;
        throw;
    }
}

bool decodeWithAVAssetReader(const std::filesystem::path& path,
                             std::uint64_t maxDecodedBytes,
                             const MixCheckpoint& checkpoint,
                             bgmedia::AudioData& out,
                             bool& hitPcmLimit,
                             std::string& detailError) {
    AVURLAsset *asset = nil;
    AVAssetReader *reader = nil;
    AVAssetReaderTrackOutput *output = nil;
    try {
        @autoreleasepool {
            NSString *filePath = [NSString stringWithUTF8String:path.c_str()];
            if (filePath == nil) {
                detailError = "invalid_path";
                return false;
            }
            NSDictionary *assetOptions = @{AVURLAssetPreferPreciseDurationAndTimingKey: @YES};
            asset = [[AVURLAsset alloc] initWithURL:[NSURL fileURLWithPath:filePath] options:assetOptions];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            NSArray<AVAssetTrack *> *tracks = [asset tracksWithMediaType:AVMediaTypeAudio];
#pragma clang diagnostic pop
            AVAssetTrack *audioTrack = tracks.firstObject;
            if (audioTrack == nil) {
                detailError = "no_audio_track";
                return false;
            }

            std::uint32_t channels = 2;
            std::uint32_t sampleRate = 48000;
            NSArray *formatDescriptions = audioTrack.formatDescriptions;
            if (formatDescriptions.count > 0) {
                CMAudioFormatDescriptionRef desc = (__bridge CMAudioFormatDescriptionRef)formatDescriptions.firstObject;
                const AudioStreamBasicDescription *asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc);
                if (asbd != nullptr) {
                    if (asbd->mChannelsPerFrame > 0 && asbd->mChannelsPerFrame <= 8) {
                        channels = asbd->mChannelsPerFrame;
                    }
                    if (asbd->mSampleRate > 0.0) {
                        sampleRate = static_cast<std::uint32_t>(asbd->mSampleRate);
                    }
                }
            }

            NSError *nsError = nil;
            reader = [[AVAssetReader alloc] initWithAsset:asset error:&nsError];
            if (reader == nil) {
                detailError = "reader_init:" + redactedNSError(nsError);
                return false;
            }

            NSDictionary *outputSettings = @{
                AVFormatIDKey: @(kAudioFormatLinearPCM),
                AVSampleRateKey: @(sampleRate),
                AVNumberOfChannelsKey: @(channels),
                AVLinearPCMBitDepthKey: @32,
                AVLinearPCMIsFloatKey: @YES,
                AVLinearPCMIsBigEndianKey: @NO,
                AVLinearPCMIsNonInterleaved: @NO,
            };
            output = [[AVAssetReaderTrackOutput alloc] initWithTrack:audioTrack outputSettings:outputSettings];
            output.alwaysCopiesSampleData = NO;
            if (![reader canAddOutput:output]) {
                detailError = "cannot_add_output";
                return false;
            }
            [reader addOutput:output];
            if (![reader startReading]) {
                detailError = "reader_start:" + redactedNSError(reader.error);
                return false;
            }

            const std::size_t maxFloats = static_cast<std::size_t>(maxDecodedBytes / sizeof(float));
            std::vector<float> samples;
            const double durationSeconds = CMTimeGetSeconds(asset.duration);
            if (durationSeconds > 0.0 && durationSeconds < 36000.0) {
                const auto estimatedFrames = static_cast<std::uint64_t>(durationSeconds * sampleRate);
                if (interleavedFloatBytes(estimatedFrames, channels) > maxDecodedBytes) {
                    [reader cancelReading];
                    hitPcmLimit = true;
                    detailError = "pcm_limit";
                    return false;
                }
                samples.reserve(static_cast<std::size_t>(estimatedFrames * channels));
            }

            while (reader.status == AVAssetReaderStatusReading) {
                SampleBufferGuard guard{[output copyNextSampleBuffer]};
                if (guard.ref == nullptr) {
                    break;
                }
                CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(guard.ref);
                if (blockBuffer == nullptr) {
                    continue;
                }
                const std::size_t byteLength = CMBlockBufferGetDataLength(blockBuffer);
                if (byteLength == 0 || (byteLength % sizeof(float)) != 0) {
                    continue;
                }
                const std::size_t floatCount = byteLength / sizeof(float);
                if (floatCount > maxFloats - samples.size()) {
                    [reader cancelReading];
                    hitPcmLimit = true;
                    detailError = "pcm_limit";
                    return false;
                }
                const std::size_t base = samples.size();
                samples.resize(base + floatCount);
                const OSStatus copyStatus = CMBlockBufferCopyDataBytes(
                    blockBuffer, 0, byteLength, samples.data() + base);
                if (copyStatus != kCMBlockBufferNoErr) {
                    [reader cancelReading];
                    detailError = "block_copy:" + std::to_string(copyStatus);
                    return false;
                }
                checkpoint();
            }

            if (reader.status != AVAssetReaderStatusCompleted) {
                detailError = "reader_status:" + std::to_string((long)reader.status) + ":" + redactedNSError(reader.error);
                return false;
            }
            if (samples.empty() || (samples.size() % channels) != 0) {
                detailError = "empty_samples";
                return false;
            }
            out.channels = channels;
            out.sampleRate = sampleRate;
            out.samples = std::move(samples);
            return out.valid();
        }
    } catch (...) {
        if (reader != nil && reader.status == AVAssetReaderStatusReading) {
            [reader cancelReading];
        }
        output = nil;
        reader = nil;
        asset = nil;
        throw;
    }
}

} // namespace

std::string redactedAudioFileSummary(const std::filesystem::path& path) {
    const std::string ext = sanitizedExtension(path);
    std::error_code ec;
    const bool exists = std::filesystem::exists(path, ec);
    long long byteCount = -1;
    if (exists && !ec) {
        const auto size = std::filesystem::file_size(path, ec);
        if (!ec) {
            byteCount = static_cast<long long>(size);
        }
    }
    std::string headHex = "none";
    if (exists) {
        std::ifstream input(path, std::ios::binary);
        std::array<unsigned char, 4> bytes{};
        input.read(reinterpret_cast<char*>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
        const auto readCount = static_cast<std::size_t>(input.gcount());
        if (readCount > 0) {
            headHex.clear();
            char pair[3];
            for (std::size_t i = 0; i < readCount; ++i) {
                std::snprintf(pair, sizeof(pair), "%02x", bytes[i]);
                headHex += pair;
            }
        } else {
            headHex = "empty";
        }
    }
    return "ext=" + ext + " bytes=" + std::to_string(byteCount) + " head=" + headHex;
}

bool decodeWithAVFoundation(const std::filesystem::path& path,
                            std::uint64_t maxDecodedBytes,
                            const MixCheckpoint& checkpoint,
                            bgmedia::AudioData& out,
                            std::string& error) {
    bool hitPcmLimit = false;
    std::string avfDetail;
    if (decodeWithAVAudioFile(path, maxDecodedBytes, checkpoint, out, hitPcmLimit, avfDetail)) {
        return true;
    }
    const std::string summary = redactedAudioFileSummary(path);
    if (hitPcmLimit) {
        error = "Audio track exceeds in-memory PCM limit (" + summary + ")";
        return false;
    }

    std::string readerDetail;
    if (decodeWithAVAssetReader(path, maxDecodedBytes, checkpoint, out, hitPcmLimit, readerDetail)) {
        return true;
    }
    if (hitPcmLimit) {
        error = "Audio track exceeds in-memory PCM limit (" + summary + ")";
        return false;
    }
    error = "Could not decode audio (" + summary + ", avf=" + avfDetail + ", reader=" + readerDetail + ")";
    return false;
}

} // namespace beygram::media
