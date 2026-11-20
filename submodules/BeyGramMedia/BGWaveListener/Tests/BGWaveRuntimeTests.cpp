// Host tests for the BG Wave listener runtime (stage 4 in docs/bg-wave-ios.md): the failure classification, and a runtime
// that is created, asked for an invite, pulled from and stopped. No network: the transport is never started.
#include "../Sources/BGWaveRuntime.hpp"

#include <cmath>
#include <cstdio>
#include <string>
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

void testClassifyFailure() {
    using S = bw::WaveSessionState;
    using T = bw::WaveTransportState;
    CHECK(bl::classifyWaveFailure(S::Idle, T::Failed, false) == bl::WaveFailureKind::None);
    CHECK(bl::classifyWaveFailure(S::LiveP2P, T::Failed, false) == bl::WaveFailureKind::None);
    CHECK(bl::classifyWaveFailure(S::P2PFailed, T::Failed, false) == bl::WaveFailureKind::LocalNetworkSuspected);
    CHECK(bl::classifyWaveFailure(S::Failed, T::Failed, false) == bl::WaveFailureKind::LocalNetworkSuspected);
    CHECK(bl::classifyWaveFailure(S::P2PFailed, T::Failed, true) == bl::WaveFailureKind::Other);
    CHECK(bl::classifyWaveFailure(S::Failed, T::Connecting, false) == bl::WaveFailureKind::Other);
}

void testRuntimeWithoutSignal() {
    bl::BGWaveRuntime runtime(bl::BGWaveRuntime::Options{});
    CHECK(runtime.state() == bw::WaveSessionState::Idle);
    CHECK(runtime.failureKind() == bl::WaveFailureKind::None);
    CHECK(!runtime.pollOutboundInvite().has_value());
    CHECK(!runtime.acceptInvite("not-a-wave-link", 1700000000));

    std::vector<float> out(480 * 2, 1.0f);
    const std::size_t frames = runtime.pullListenerPcm(out.data(), 480, 48000);
    CHECK(frames <= 480);
    for (float sample : out) {
        CHECK(std::isfinite(sample));
    }

    // The host tap goes through pushHostPcm, which a listener runtime accepts as a no-op.
    std::vector<float> block(480 * 2, 0.0f);
    runtime.hostTap().onPcmRendered(block.data(), 480, 48000);

    runtime.stop(false, 0);
}

}  // namespace

int main() {
    testClassifyFailure();
    testRuntimeWithoutSignal();
    if (gFailures == 0) {
        std::printf("BGWaveRuntimeTests: all checks passed\n");
        return 0;
    }
    std::printf("BGWaveRuntimeTests: %d check(s) failed\n", gFailures);
    return 1;
}
