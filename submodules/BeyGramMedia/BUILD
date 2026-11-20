load("@rules_cc//cc:cc_library.bzl", "cc_library")
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
    visibility = ["//visibility:private"],
    deps = [
        ":BGMediaKissFFT",
    ],
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
    ],
    visibility = [
        "//visibility:public",
    ],
    deps = [
        ":BGMediaCore",
    ],
)
