load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("@rules_cc//cc:cc_test.bzl", "cc_test")
load("@rules_cc//cc:objc_library.bzl", "objc_library")

# BG Wave iOS listener layer, stages 2 to 4 in docs/bg-wave-ios.md. The output and the host tap know nothing about the
# session: the caller passes a pull block or a sink. The session that owns the codec, the transport and BGWaveSession
# is BGWaveListenerSession (stage 4), added in its own PR.

# Header-only: forwards IPcmOutputTap calls to a C sink without allocating.
cc_library(
    name = "BGWavePcmTap",
    hdrs = ["Sources/BGWavePcmTap.hpp"],
    copts = ["-std=c++20"],
    visibility = ["//visibility:public"],
    deps = ["//submodules/BeyGramMedia:BGMediaCore"],
)

objc_library(
    name = "BGWaveListenerOutput",
    srcs = ["Sources/BGWaveListenerOutput.mm"],
    hdrs = ["PublicHeaders/BGWaveListener/BGWaveListenerOutput.h"],
    includes = ["PublicHeaders"],
    copts = ["-fobjc-arc"],
    sdk_frameworks = [
        "AVFoundation",
        "Foundation",
    ],
    visibility = ["//visibility:public"],
)

# Host test, no codesigning. It runs the Opus codec, the libdatachannel transport (created and closed, never started,
# so it touches no network) and the listener pipeline, and it checks the host tap:
#   ./build-input/bazel-9.2.0-darwin-arm64 test //submodules/BeyGramMedia/BGWaveListener:BGWaveAdaptersTests --test_output=all
cc_test(
    name = "BGWaveAdaptersTests",
    srcs = ["Tests/BGWaveAdaptersTests.cpp"],
    copts = ["-std=c++20"],
    deps = [
        ":BGWavePcmTap",
        "//submodules/BeyGramMedia:BGMediaCore",
        "//submodules/BeyGramMedia:BGWaveOpusAdapter",
        "//submodules/BeyGramMedia:BGWaveWebRtcAdapter",
    ],
)
