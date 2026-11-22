load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("@rules_cc//cc:cc_test.bzl", "cc_test")
load("@rules_cc//cc:objc_library.bzl", "objc_library")

# BG Mix (AutoMix) and BG Beat for iOS. The C++20 core lives in the BG-Media
# git submodule (BGMediaCore); this package only adds the iOS adapters:
# AVFoundation decoding and AVAudioEngine output.

# kissfft is plain C and must not get the C++ -std flag, so it is its own target.
cc_library(
    name = "BGMediaKissFFT",
    srcs = [
        "BGMediaCore/third_party/kissfft/kiss_fft.c",
        "BGMediaCore/third_party/kissfft/kiss_fftr.c",
    ],
    hdrs = glob([
        "BGMediaCore/third_party/kissfft/*.h",
    ]),
    includes = [
        "BGMediaCore/third_party/kissfft",
    ],
    visibility = ["//visibility:private"],
)

cc_library(
    name = "BGMediaCore",
    srcs = [
        "BGMediaCore/src/audio/AudioData.cpp",
        "BGMediaCore/src/audio/WavDecoder.cpp",
        "BGMediaCore/src/analysis/Analyzer.cpp",
        "BGMediaCore/src/analysis/SpectralAnalysis.cpp",
        "BGMediaCore/src/analysis/TempoEstimator.cpp",
        "BGMediaCore/src/analysis/BeatTracker.cpp",
        "BGMediaCore/src/analysis/EventDetection.cpp",
        "BGMediaCore/src/analysis/AnalysisConfig.cpp",
        "BGMediaCore/src/cache/AnalysisCache.cpp",
        "BGMediaCore/src/sync/PlaybackClock.cpp",
        "BGMediaCore/src/choreography/Choreography.cpp",
        "BGMediaCore/src/mix/MixTypes.cpp",
        "BGMediaCore/src/mix/PcmTrack.cpp",
        "BGMediaCore/src/mix/MixFeatureMap.cpp",
        "BGMediaCore/src/mix/MixFeatureCache.cpp",
        "BGMediaCore/src/mix/VocalDetector.cpp",
        "BGMediaCore/src/mix/HarmonicAnalyzer.cpp",
        "BGMediaCore/src/mix/TimeStretch.cpp",
        "BGMediaCore/src/mix/SpectralEq.cpp",
        "BGMediaCore/src/mix/MixPlanner.cpp",
        "BGMediaCore/src/mix/MixEngine.cpp",
        "BGMediaCore/src/mix/MixSession.cpp",
        "BGMediaCore/src/mix/MixSync.cpp",
        # BG Wave core (portable part: ring buffer, resampler, codec framing, jitter buffer, signaling,
        # transport, audio pipeline). The libopus and libdatachannel adapters are not built on iOS yet.
        "BGMediaCore/src/wave/WaveRingBuffer.cpp",
        "BGMediaCore/src/wave/WaveResampler.cpp",
        "BGMediaCore/src/wave/WaveCodec.cpp",
        "BGMediaCore/src/wave/WaveJitterBuffer.cpp",
        "BGMediaCore/src/wave/WaveSignaling.cpp",
        "BGMediaCore/src/wave/WaveTransport.cpp",
        "BGMediaCore/src/wave/WaveAudioPipeline.cpp",
    ],
    hdrs = glob([
        "BGMediaCore/include/**/*.h",
        "BGMediaCore/include/**/*.hpp",
        "BGMediaCore/src/**/*.h",
        "BGMediaCore/src/**/*.hpp",
    ], allow_empty = True),
    includes = [
        "BGMediaCore/include",
        "BGMediaCore/src",
    ],
    copts = [
        "-std=c++20",
    ],
    linkopts = [
        "-lpthread",
    ],
    # Subpackages (BGWaveCore) build on the core; nothing outside BeyGramMedia does.
    visibility = ["//submodules/BeyGramMedia:__subpackages__"],
    deps = [
        ":BGMediaKissFFT",
    ],
)

# BG Wave adapter sources for BGWaveCore (submodules/BeyGramMedia/BGWaveCore). They are not part of the
# BGMediaCore library above: the WebRTC and libopus adapters have their own dependencies. The paths are listed
# one by one, so a moved or missing file fails the build instead of exporting nothing.
filegroup(
    name = "BGWaveAdapterSources",
    srcs = [
        "BGMediaCore/adapters/wave_webrtc/include/bgmedia/wave/WebRtcWaveTransport.hpp",
        "BGMediaCore/adapters/wave_webrtc/src/WebRtcWaveTransport.cpp",
        "BGMediaCore/adapters/wave_opus/include/bgmedia/wave/OpusWaveCodec.hpp",
        "BGMediaCore/adapters/wave_opus/src/OpusWaveCodec.cpp",
    ],
    visibility = ["//submodules/BeyGramMedia:__subpackages__"],
)

# Pure C++ PCM limits for the iOS track pipeline. The host test runs with `bazel test` on a Mac.
cc_library(
    name = "BGMediaPcmLimits",
    hdrs = ["Sources/BGMediaPcmLimits.hpp"],
    visibility = ["//visibility:private"],
)

cc_test(
    name = "BGMediaPcmLimitsTests",
    srcs = ["Tests/BGMediaPcmLimitsTests.cpp"],
    copts = ["-std=c++20"],
    deps = [":BGMediaPcmLimits"],
)

# Pure mapping from the MixSession snapshot to the player's published state. Host test as above.
cc_library(
    name = "BGMediaMixState",
    hdrs = ["Sources/BGMediaMixState.hpp"],
    deps = [":BGMediaCore"],
    visibility = ["//visibility:private"],
)

cc_test(
    name = "BGMediaMixStateTests",
    srcs = ["Tests/BGMediaMixStateTests.cpp"],
    copts = ["-std=c++20"],
    deps = [":BGMediaMixState"],
)

objc_library(
    name = "BeyGramMedia",
    enable_modules = True,
    module_name = "BeyGramMedia",
    srcs = glob([
        "Sources/**/*.mm",
        "Sources/**/*.cpp",
        "Sources/**/*.hpp",
        "Sources/**/*.h",
    ], allow_empty = True),
    hdrs = glob([
        "PublicHeaders/**/*.h",
    ]),
    includes = [
        "PublicHeaders",
    ],
    copts = [
        "-std=c++20",
        "-fobjc-arc",
    ],
    sdk_frameworks = [
        "Foundation",
        "AVFoundation",
        "QuartzCore",
        "UIKit",
        "UniformTypeIdentifiers",
    ],
    visibility = [
        "//visibility:public",
    ],
    deps = [
        ":BGMediaCore",
    ],
)

# BG Wave adapters for the iOS session layer (stage 3 in docs/bg-wave-ios.md). Each adapter is its own target, because
# its header has to be in `hdrs` to be visible to //submodules/BeyGramMedia/BGWaveListener, and the filegroup above
# cannot split headers from sources. The files are the ones BGWaveAdapterSources lists.
cc_library(
    name = "BGWaveOpusAdapter",
    srcs = ["BGMediaCore/adapters/wave_opus/src/OpusWaveCodec.cpp"],
    hdrs = ["BGMediaCore/adapters/wave_opus/include/bgmedia/wave/OpusWaveCodec.hpp"],
    includes = ["BGMediaCore/adapters/wave_opus/include"],
    copts = ["-std=c++20"],
    visibility = ["//submodules/BeyGramMedia:__subpackages__"],
    deps = [
        ":BGMediaCore",
        "//third-party/opus:opus",
    ],
)

# libdatachannel sets -Drtc=bgrtc through its `defines`, so the adapter's rtc:: names resolve to bgrtc:: here too.
cc_library(
    name = "BGWaveWebRtcAdapter",
    srcs = ["BGMediaCore/adapters/wave_webrtc/src/WebRtcWaveTransport.cpp"],
    hdrs = ["BGMediaCore/adapters/wave_webrtc/include/bgmedia/wave/WebRtcWaveTransport.hpp"],
    includes = ["BGMediaCore/adapters/wave_webrtc/include"],
    copts = ["-std=c++20"],
    visibility = ["//submodules/BeyGramMedia:__subpackages__"],
    deps = [
        ":BGMediaCore",
        "//third-party/libdatachannel:libdatachannel",
    ],
)
