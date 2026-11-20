// Host tests for the BG Wave iOS adapters (stages 2 and 3 in docs/bg-wave-ios.md): the Opus codec, the libdatachannel
// transport and the listener pipeline, plus the host tap. Plain C++20 with a CHECK macro, like BGWaveCoreTests. The
// transport is created and closed, never started, so the test touches no network.
#include "../Sources/BGWavePcmTap.hpp"

#include "bgmedia/wave/OpusWaveCodec.hpp"
#include "bgmedia/wave/WaveAudioPipeline.hpp"
#include "bgmedia/wave/WaveCodec.hpp"
#include "bgmedia/wave/WaveTransport.hpp"
#include "bgmedia/wave/WaveTypes.hpp"
#include "bgmedia/wave/WebRtcWaveTransport.hpp"

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <memory>
#include <vector>

namespace {

namespace bw = bgmedia::wave;
namespace bl = beygram::wave;

int gFailures = 0;

#define CHECK(condition)                                                                  \
    do {                                                                                  \
        if (!(condition)) {                                                               \
            std::fprintf(stderr, "CHECK failed at line %d: %s\n", __LINE__, #condition);  \
            ++gFailures;                                                                  \
        }                                                                                 \
    } while (0)

struct TapCounter {
    std::size_t frames = 0;
    std::uint32_t lastRate = 0;
};

void countSink(void* context, const float* /*interleavedStereo*/, std::size_t frames, std::uint32_t sampleRate) noexcept {
    auto* counter = static_cast<TapCounter*>(context);
    counter->frames += frames;
    counter->lastRate = sampleRate;
}

void testOpusRoundTrip() {
    bw::OpusWaveCodec codec;
    CHECK(codec.isReady());
    CHECK(codec.sampleRate() == bw::kWaveSampleRate);
    CHECK(codec.channels() == bw::kWaveChannels);

    const std::size_t samples = codec.frameSamples() * codec.channels();
    std::vector<float> pcm(samples, 0.25f);
    std::vector<std::uint8_t> payload;
    CHECK(codec.encode(pcm, payload));
    CHECK(!payload.empty());

    std::vector<float> decoded(samples, 0.0f);
    CHECK(codec.decode(payload, decoded));
    CHECK(codec.decodePlc(decoded));
    for (float sample : decoded) {
        CHECK(std::isfinite(sample));
    }
}

void testTapForwardsFrames() {
    TapCounter counter;
    bl::BGWavePcmTap tap(countSink, &counter);
    std::vector<float> block(480 * 2, 0.0f);
    tap.onPcmRendered(block.data(), 480, 48000);
    CHECK(counter.frames == 480);
    CHECK(counter.lastRate == 48000);

    bl::BGWavePcmTap nullTap(nullptr, nullptr);
    nullTap.onPcmRendered(block.data(), 480, 48000);
}

void testListenerPipelinePullsWithoutSignal() {
    bw::WebRtcTransportConfig transportConfig;
    transportConfig.role = bw::WaveRole::Listener;
    auto transport = std::make_shared<bw::WebRtcWaveTransport>(transportConfig);

    bw::WavePipelineConfig pipelineConfig;
    pipelineConfig.role = bw::WaveRole::Listener;
    auto codec = std::make_shared<bw::OpusWaveCodec>();
    auto pipeline = std::make_shared<bw::WaveAudioPipeline>(pipelineConfig, codec, transport);
    CHECK(pipeline->state() == bw::WaveSessionState::Idle);

    std::vector<float> out(480 * 2, 0.0f);
    const std::size_t written = pipeline->pullListenerPcm(out.data(), 480, 48000);
    CHECK(written <= 480);
    for (float sample : out) {
        CHECK(std::isfinite(sample));
    }
    transport->close();
}

}  // namespace

int main() {
    testOpusRoundTrip();
    testTapForwardsFrames();
    testListenerPipelinePullsWithoutSignal();
    if (gFailures == 0) {
        std::printf("BGWaveAdaptersTests: all checks passed\n");
        return 0;
    }
    std::printf("BGWaveAdaptersTests: %d check(s) failed\n", gFailures);
    return 1;
}
