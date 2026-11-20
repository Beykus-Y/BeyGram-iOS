// Host test for Sources/BGMediaPcmLimits.hpp. Plain CHECK + main(), like the other C++ units in this repo.

#include "../Sources/BGMediaPcmLimits.hpp"

#include <cstdio>
#include <stdexcept>

namespace {

int failures = 0;

#define CHECK_TRUE(cond)                                                     \
    do {                                                                     \
        if (!(cond)) {                                                       \
            std::fprintf(stderr, "%s:%d: CHECK_TRUE(%s) failed\n", __FILE__, \
                         __LINE__, #cond);                                   \
            ++failures;                                                      \
        }                                                                    \
    } while (0)

template <typename Fn>
bool throwsLength(Fn fn) {
    try {
        fn();
    } catch (const std::length_error&) {
        return true;
    } catch (...) {
    }
    return false;
}

void testInterleavedBytes() {
    using beygram::media::interleavedFloatBytes;
    CHECK_TRUE(interleavedFloatBytes(10, 2) == 80);
    CHECK_TRUE(interleavedFloatBytes(0, 2) == 0);
    CHECK_TRUE(interleavedFloatBytes(UINT64_MAX, 2) == UINT64_MAX);
}

void testMixerLimitMatchesDesktopRule() {
    using beygram::media::kMixMaxTrackPcmBytes;
    using beygram::media::mixerPcmFits;
    // 128 MiB at 48 kHz stereo holds 16_777_216 frames (about 5 min 49 s).
    CHECK_TRUE(mixerPcmFits(16777216, 48000, 48000, 2, kMixMaxTrackPcmBytes));
    CHECK_TRUE(!mixerPcmFits(16777216 + 1000, 48000, 48000, 2, kMixMaxTrackPcmBytes));
    // A 6 minute 48 kHz stereo track does not fit; the rejection happens before any analysis.
    CHECK_TRUE(!mixerPcmFits(48000ull * 360, 48000, 48000, 2, kMixMaxTrackPcmBytes));
    // 5 minutes at 44.1 kHz is resampled to 48 kHz and still fits.
    CHECK_TRUE(mixerPcmFits(44100ull * 300, 44100, 48000, 2, kMixMaxTrackPcmBytes));
    // Mono folds to one channel, so it holds twice the frames.
    CHECK_TRUE(mixerPcmFits(48000ull * 600, 48000, 48000, 1, kMixMaxTrackPcmBytes));
    // Degenerate inputs never fit.
    CHECK_TRUE(!mixerPcmFits(100, 0, 48000, 2, kMixMaxTrackPcmBytes));
    CHECK_TRUE(!mixerPcmFits(100, 48000, 48000, 0, kMixMaxTrackPcmBytes));
    CHECK_TRUE(!mixerPcmFits(100, 48000, 48000, 2, 0));
}

void testBudgetConstantsAreConsistent() {
    using namespace beygram::media;
    CHECK_TRUE(kMixMaxTrackPcmBytes == 128 * kMixMiB);
    CHECK_TRUE(kMixPreparationPcmReserve >= kMixMaxTrackPcmBytes);
    CHECK_TRUE(kMixSessionPcmBudget == kMixMaxTrackPcmBytes + kMixPreparationPcmReserve);
    // Same invariant MixSession's constructor checks: a current track plus one preparation fits.
    CHECK_TRUE(kMixMaxTrackPcmBytes <= kMixSessionPcmBudget - kMixPreparationPcmReserve);
}

void testBuilderInterleavesPlanarBlocks() {
    beygram::media::InterleavedPcmBuilder builder(2, 6, 1024);
    const float left1[] = {1, 2, 3};
    const float right1[] = {-1, -2, -3};
    const float* planes1[] = {left1, right1};
    builder.appendPlanar(planes1, 3);
    const float left2[] = {4, 5, 6};
    const float right2[] = {-4, -5, -6};
    const float* planes2[] = {left2, right2};
    builder.appendPlanar(planes2, 3);
    CHECK_TRUE(builder.frames() == 6);
    const std::vector<float> samples = builder.take();
    CHECK_TRUE(samples.size() == 12);
    const float expected[] = {1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6, -6};
    for (std::size_t i = 0; i < 12 && i < samples.size(); ++i) {
        CHECK_TRUE(samples[i] == expected[i]);
    }
    CHECK_TRUE(builder.frames() == 0);
}

void testBuilderRejectsOversizedInput() {
    using beygram::media::InterleavedPcmBuilder;
    // 1024 bytes hold 128 stereo frames; 129 do not.
    CHECK_TRUE(throwsLength([] { InterleavedPcmBuilder b(2, 129, 1024); }));
    InterleavedPcmBuilder ok(2, 128, 1024);
    const float zeros[128] = {};
    const float* planes[] = {zeros, zeros};
    ok.appendPlanar(planes, 128);
    CHECK_TRUE(throwsLength([&] { ok.appendPlanar(planes, 1); }));
    bool threw = false;
    try {
        InterleavedPcmBuilder none(0, 10, 1024);
    } catch (const std::invalid_argument&) {
        threw = true;
    }
    CHECK_TRUE(threw);
}

} // namespace

int main() {
    testInterleavedBytes();
    testMixerLimitMatchesDesktopRule();
    testBudgetConstantsAreConsistent();
    testBuilderInterleavesPlanarBlocks();
    testBuilderRejectsOversizedInput();
    if (failures != 0) {
        std::fprintf(stderr, "%d check(s) failed\n", failures);
        return 1;
    }
    std::printf("BGMediaPcmLimitsTests: all checks passed\n");
    return 0;
}
