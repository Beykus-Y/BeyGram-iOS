#include "bgmedia/audio/AudioData.hpp"
#include "bgmedia/mix/MixEngine.hpp"
#include "bgmedia/mix/MixPlanner.hpp"
#include "bgmedia/mix/MixSession.hpp"
#include "submodules/BeyGramMedia/Sources/BGMediaMixPreparation.hpp"
#include "submodules/BeyGramMedia/Sources/BGMediaMixState.hpp"

#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <filesystem>
#include <string>
#include <thread>
#include <unordered_map>
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

constexpr std::uint32_t kRate = 48000;

bgmedia::AudioData makeSine(double freqHz, double seconds) {
    bgmedia::AudioData data;
    data.sampleRate = kRate;
    data.channels = 2;
    const std::size_t frames = static_cast<std::size_t>(seconds * kRate);
    data.samples.resize(frames * 2);
    for (std::size_t i = 0; i < frames; ++i) {
        const float s = static_cast<float>(0.5 * std::sin(2.0 * M_PI * freqHz * static_cast<double>(i) / kRate));
        data.samples[2 * i] = s;
        data.samples[2 * i + 1] = s;
    }
    return data;
}

// Estimates dominant frequency of stereo interleaved PCM using zero-crossing rate on the left channel.
double estimateFrequencyHz(const std::vector<float>& stereoPcm) {
    if (stereoPcm.size() < 200) {
        return 0.0;
    }
    int crossings = 0;
    const std::size_t frames = stereoPcm.size() / 2;
    for (std::size_t i = 1; i < frames; ++i) {
        const float prev = stereoPcm[2 * (i - 1)];
        const float curr = stereoPcm[2 * i];
        if ((prev <= 0.0f && curr > 0.0f) || (prev >= 0.0f && curr < 0.0f)) {
            ++crossings;
        }
    }
    const double seconds = static_cast<double>(frames) / static_cast<double>(kRate);
    return (static_cast<double>(crossings) / 2.0) / seconds;
}

// Mirrors BGMixPlayer.mm resetDecksSynchronously.
void resetDecksSynchronously(bgmedia::mix::MixEngine& engine, bgmedia::mix::MixSession& session) {
    std::vector<float> scratch(2048, 0.0f);
    session.stopAll();
    engine.render(scratch.data(), 1024);
    engine.render(scratch.data(), 1);
    session.clearQueue();
    session.update();
    engine.render(scratch.data(), 1);
    session.update();
}

bool waitUntilTrackReadyOrPlaying(bgmedia::mix::MixEngine& engine,
                                  bgmedia::mix::MixSession& session,
                                  std::uint64_t trackId,
                                  int maxSteps = 2000) {
    std::vector<float> scratch(2048, 0.0f);
    for (int i = 0; i < maxSteps; ++i) {
        session.update();
        engine.render(scratch.data(), 512);
        const auto snap = session.snapshot();
        for (const auto& item : snap.queue) {
            if (item.id == trackId &&
                (item.state == bgmedia::mix::QueueState::Ready ||
                 item.state == bgmedia::mix::QueueState::Playing)) {
                return true;
            }
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(2));
    }
    return false;
}

void testReplaceQueueWhilePlayingNeverHitsBusyDeckAndChangesRealAudio() {
    std::unordered_map<std::string, bgmedia::AudioData> fixtures;
    fixtures["track_a.wav"] = makeSine(440.0, 3.0);
    fixtures["track_b.wav"] = makeSine(660.0, 3.0);
    fixtures["track_c.wav"] = makeSine(880.0, 3.0);

    bgmedia::mix::MixEngine engine(kRate);
    beygram::media::MixPreparationOptions options;
    options.useCache = false;
    options.targetSampleRate = kRate;

    bgmedia::mix::MixSession session(
        engine,
        [&](const std::filesystem::path& path, bgmedia::mix::PreparedMixTrack& out,
            std::string& error, std::function<void(float, std::string_view)> progress) {
            auto decoder = [&](const std::filesystem::path& p, std::uint64_t,
                               const beygram::media::MixCheckpoint& cp,
                               bgmedia::AudioData& decoded, std::string& err) -> bool {
                auto it = fixtures.find(p.filename().string());
                if (it == fixtures.end()) {
                    err = "missing fixture";
                    return false;
                }
                decoded = it->second;
                cp();
                return true;
            };
            return beygram::media::prepareMixTrack(path, decoder, options, out, error, progress);
        },
        bgmedia::mix::MixPlanner{},
        bgmedia::mix::MixPcmBudget{beygram::media::kMixMaxTrackPcmBytes,
                                   beygram::media::kMixPreparationPcmReserve,
                                   beygram::media::kMixSessionPcmBudget});

    auto playAndMeasureHz = [&](const std::string& name) -> double {
        resetDecksSynchronously(engine, session);
        CHECK(engine.retiredPcmBytes() == 0);
        const std::uint64_t id = session.addTrack(std::filesystem::path(name));
        CHECK(id != 0);
        session.play();
        CHECK(waitUntilTrackReadyOrPlaying(engine, session, id));

        // Pump a few updates so deck A is loaded and playing.
        std::vector<float> buf(4096 * 2, 0.0f);
        for (int i = 0; i < 6; ++i) {
            session.update();
            engine.render(buf.data(), 4096);
        }
        const auto snap = session.snapshot();
        CHECK(snap.lastError.find("busy deck") == std::string::npos);
        CHECK(beygram::media::currentTrackId(snap.engine) == id);
        CHECK(beygram::media::transportOf(snap.engine) == beygram::media::MixTransport::Playing);
        return estimateFrequencyHz(buf);
    };

    // Rapid A -> B -> C switches while previous track is actively sounding.
    const double hzA = playAndMeasureHz("track_a.wav");
    const double hzB = playAndMeasureHz("track_b.wav");
    const double hzC = playAndMeasureHz("track_c.wav");

    CHECK(std::fabs(hzA - 440.0) < 35.0);
    CHECK(std::fabs(hzB - 660.0) < 35.0);
    CHECK(std::fabs(hzC - 880.0) < 35.0);
}

void testInvalidTransitionPlanCancelsCleanlyWithoutStuckRetry() {
    std::unordered_map<std::string, bgmedia::AudioData> fixtures;
    // Very short tracks (0.4s) where crossfade planning fails.
    fixtures["short_a.wav"] = makeSine(440.0, 0.4);
    fixtures["short_b.wav"] = makeSine(880.0, 0.4);

    bgmedia::mix::MixEngine engine(kRate);
    beygram::media::MixPreparationOptions options;
    options.useCache = false;
    options.targetSampleRate = kRate;

    bgmedia::mix::MixSession session(
        engine,
        [&](const std::filesystem::path& path, bgmedia::mix::PreparedMixTrack& out,
            std::string& error, std::function<void(float, std::string_view)> progress) {
            auto decoder = [&](const std::filesystem::path& p, std::uint64_t,
                               const beygram::media::MixCheckpoint& cp,
                               bgmedia::AudioData& decoded, std::string& err) -> bool {
                auto it = fixtures.find(p.filename().string());
                if (it == fixtures.end()) {
                    err = "missing fixture";
                    return false;
                }
                decoded = it->second;
                cp();
                return true;
            };
            return beygram::media::prepareMixTrack(path, decoder, options, out, error, progress);
        },
        bgmedia::mix::MixPlanner{},
        bgmedia::mix::MixPcmBudget{beygram::media::kMixMaxTrackPcmBytes,
                                   beygram::media::kMixPreparationPcmReserve,
                                   beygram::media::kMixSessionPcmBudget});

    const std::uint64_t idA = session.addTrack("short_a.wav");
    const std::uint64_t idB = session.addTrack("short_b.wav");
    session.play();
    CHECK(waitUntilTrackReadyOrPlaying(engine, session, idA));
    CHECK(waitUntilTrackReadyOrPlaying(engine, session, idB));

    session.next();
    if (!engine.transitionActive()) {
        // Same recovery BGMixPlayer::tryStartNextTransition performs: cancel pending nextRequested_
        // then fall back to atomic replaceQueueAndPlayTrack(B).
        session.cancelTransition();
        resetDecksSynchronously(engine, session);
        const std::uint64_t idB2 = session.addTrack("short_b.wav");
        session.play();
        CHECK(waitUntilTrackReadyOrPlaying(engine, session, idB2));
        std::vector<float> buf(4096 * 2, 0.0f);
        for (int i = 0; i < 4; ++i) {
            session.update();
            engine.render(buf.data(), 4096);
        }
        const auto snap = session.snapshot();
        CHECK(beygram::media::currentTrackId(snap.engine) == idB2);
        CHECK(std::fabs(estimateFrequencyHz(buf) - 880.0) < 40.0);
    }
}

} // namespace

int main() {
    testReplaceQueueWhilePlayingNeverHitsBusyDeckAndChangesRealAudio();
    testInvalidTransitionPlanCancelsCleanlyWithoutStuckRetry();
    if (gFailures > 0) {
        std::fprintf(stderr, "BGMediaMixSessionTransitionTests: %d failure(s)\n", gFailures);
        return 1;
    }
    std::printf("BGMediaMixSessionTransitionTests: ALL PASSED\n");
    return 0;
}
