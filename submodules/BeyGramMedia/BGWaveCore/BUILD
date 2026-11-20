load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("@rules_cc//cc:cc_test.bzl", "cc_test")

# BG Wave session layer for iOS, transport-independent: invite links (BgWaveLink.kt's two wrappers) and a Host or
# Listener session over the BG-Media pipeline (WaveAudioPipeline). It needs //submodules/BeyGramMedia:BGMediaCore at
# the BG-Media dev pin, whose srcs include src/wave/*. Codec and transport are injected by the caller.
cc_library(
    name = "BGWaveCore",
    srcs = [
        "BGWaveInvite.cpp",
        "BGWaveSession.cpp",
    ],
    hdrs = [
        "BGWaveInvite.hpp",
        "BGWaveSession.hpp",
    ],
    copts = ["-std=c++20"],
    visibility = ["//submodules/BeyGramMedia:__subpackages__"],
    deps = ["//submodules/BeyGramMedia:BGMediaCore"],
)

# Host test, no codesigning:
#   ./build-input/bazel-9.2.0-darwin-arm64 test //submodules/BeyGramMedia/BGWaveCore:BGWaveCoreTests --test_output=all
cc_test(
    name = "BGWaveCoreTests",
    srcs = ["Tests/BGWaveCoreTests.cpp"],
    copts = ["-std=c++20"],
    deps = [":BGWaveCore"],
)
