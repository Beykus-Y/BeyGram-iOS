#include "submodules/BeyGramMedia/Sources/BGMediaAVFoundationDecoder.hpp"

#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

int gFailures = 0;

void check(bool condition, const char* expr, int line) {
    if (!condition) {
        std::fprintf(stderr, "FAIL line %d: %s\n", line, expr);
        ++gFailures;
    }
}

#define CHECK(expr) check((expr), #expr, __LINE__)

void writeLe16(std::ofstream& out, std::uint16_t v) {
    char b[2] = {static_cast<char>(v & 0xFF), static_cast<char>((v >> 8) & 0xFF)};
    out.write(b, 2);
}

void writeLe32(std::ofstream& out, std::uint32_t v) {
    char b[4] = {
        static_cast<char>(v & 0xFF),
        static_cast<char>((v >> 8) & 0xFF),
        static_cast<char>((v >> 16) & 0xFF),
        static_cast<char>((v >> 24) & 0xFF),
    };
    out.write(b, 4);
}

void writeTestWav(const std::filesystem::path& path, std::uint32_t sampleRate, std::uint32_t frames) {
    const std::uint16_t channels = 2;
    const std::uint16_t bitsPerSample = 16;
    const std::uint32_t dataSize = frames * channels * (bitsPerSample / 8);
    std::ofstream out(path, std::ios::binary);
    out.write("RIFF", 4);
    writeLe32(out, 36 + dataSize);
    out.write("WAVE", 4);
    out.write("fmt ", 4);
    writeLe32(out, 16);
    writeLe16(out, 1); // PCM
    writeLe16(out, channels);
    writeLe32(out, sampleRate);
    writeLe32(out, sampleRate * channels * (bitsPerSample / 8));
    writeLe16(out, channels * (bitsPerSample / 8));
    writeLe16(out, bitsPerSample);
    out.write("data", 4);
    writeLe32(out, dataSize);
    for (std::uint32_t i = 0; i < frames; ++i) {
        const double angle = 2.0 * M_PI * 440.0 * static_cast<double>(i) / static_cast<double>(sampleRate);
        const auto sample = static_cast<std::int16_t>(std::lround(12000.0 * std::sin(angle)));
        writeLe16(out, static_cast<std::uint16_t>(sample));
        writeLe16(out, static_cast<std::uint16_t>(sample));
    }
}

void testWavDecodeAndEOF(const std::filesystem::path& dir) {
    const auto wavPath = dir / "tone.wav";
    writeTestWav(wavPath, 44100, 44100);
    bgmedia::AudioData out;
    std::string error;
    int checkpoints = 0;
    const bool ok = beygram::media::decodeWithAVFoundation(
        wavPath,
        beygram::media::kMixMaxTrackPcmBytes,
        [&]() { ++checkpoints; },
        out,
        error);
    CHECK(ok);
    CHECK(error.empty());
    CHECK(out.channels == 2);
    CHECK(out.sampleRate == 44100);
    CHECK(out.samples.size() == 44100 * 2);
    CHECK(checkpoints >= 1);
}

void testM4ADecodeAndWrongExtension(const std::filesystem::path& dir) {
    const auto wavPath = dir / "source.wav";
    const auto m4aPath = dir / "tone.m4a";
    writeTestWav(wavPath, 44100, 44100);

    const std::string cmd =
        "/usr/bin/afconvert -f m4af -d aac '" + wavPath.string() + "' '" + m4aPath.string() + "'";
    const int status = std::system(cmd.c_str());
    CHECK(status == 0);
    if (status != 0) {
        return;
    }

    // 1) Normal .m4a decode
    {
        bgmedia::AudioData out;
        std::string error;
        const bool ok = beygram::media::decodeWithAVFoundation(
            m4aPath, beygram::media::kMixMaxTrackPcmBytes, []() {}, out, error);
        CHECK(ok);
        CHECK(error.empty());
        CHECK(out.channels == 2);
        CHECK(out.sampleRate == 44100);
        CHECK(out.samples.size() >= 40000 * 2);
    }

    // 2) M4A bytes stored under .mp3 extension (legacy cache regression)
    {
        const auto misnamedPath = dir / "legacy-m4a-as-mp3.mp3";
        std::filesystem::copy_file(m4aPath, misnamedPath, std::filesystem::copy_options::overwrite_existing);
        bgmedia::AudioData out;
        std::string error;
        const bool ok = beygram::media::decodeWithAVFoundation(
            misnamedPath, beygram::media::kMixMaxTrackPcmBytes, []() {}, out, error);
        CHECK(ok);
        CHECK(error.empty());
        CHECK(out.channels == 2);
        CHECK(out.samples.size() >= 40000 * 2);
    }
}

void testCorruptFileRedactedDiagnostic(const std::filesystem::path& dir) {
    const auto badPath = dir / "secret-token-should-not-leak.mp3";
    {
        std::ofstream out(badPath, std::ios::binary);
        out << "<!DOCTYPE html><html>error</html>";
    }
    bgmedia::AudioData out;
    std::string error;
    const bool ok = beygram::media::decodeWithAVFoundation(
        badPath, beygram::media::kMixMaxTrackPcmBytes, []() {}, out, error);
    CHECK(!ok);
    CHECK(error.find("ext=mp3") != std::string::npos);
    CHECK(error.find("head=3c21444f") != std::string::npos);
    CHECK(error.find("secret-token") == std::string::npos);
}

void testPcmLimitRefused(const std::filesystem::path& dir) {
    const auto wavPath = dir / "limit.wav";
    writeTestWav(wavPath, 44100, 44100);
    bgmedia::AudioData out;
    std::string error;
    const bool ok = beygram::media::decodeWithAVFoundation(
        wavPath, 1024, []() {}, out, error);
    CHECK(!ok);
    CHECK(error.find("in-memory PCM limit") != std::string::npos);
}

void testCheckpointCancellationPropagates(const std::filesystem::path& dir) {
    const auto wavPath = dir / "cancel.wav";
    writeTestWav(wavPath, 44100, 44100);
    bgmedia::AudioData out;
    std::string error;
    bool caught = false;
    try {
        (void)beygram::media::decodeWithAVFoundation(
            wavPath,
            beygram::media::kMixMaxTrackPcmBytes,
            []() { throw std::runtime_error("cancelled"); },
            out,
            error);
    } catch (const std::runtime_error& ex) {
        caught = (std::string(ex.what()) == "cancelled");
    }
    CHECK(caught);
}

} // namespace

int main() {
    const auto dir = std::filesystem::temp_directory_path() / "bgmedia_avf_decoder_tests";
    std::error_code ec;
    std::filesystem::remove_all(dir, ec);
    std::filesystem::create_directories(dir, ec);

    testWavDecodeAndEOF(dir);
    testM4ADecodeAndWrongExtension(dir);
    testCorruptFileRedactedDiagnostic(dir);
    testPcmLimitRefused(dir);
    testCheckpointCancellationPropagates(dir);

    std::filesystem::remove_all(dir, ec);
    if (gFailures > 0) {
        std::fprintf(stderr, "BGMediaAVFoundationDecoderTests: %d failure(s)\n", gFailures);
        return 1;
    }
    std::printf("BGMediaAVFoundationDecoderTests: ALL PASSED\n");
    return 0;
}
