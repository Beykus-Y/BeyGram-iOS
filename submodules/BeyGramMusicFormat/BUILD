load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library", "swift_test")

# Pure Foundation model of the .bgmusic v1 snapshot (docs/formats/bgmusic-v1.md in BeyGram):
# text cleaning, strict JSON, manifest, ZIP container with a DEFLATE reader, and track keys shared with Android.
# No Postbox, no UIKit.
swift_library(
    name = "BeyGramMusicFormat",
    module_name = "BeyGramMusicFormat",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    deps = [],
    visibility = [
        "//visibility:public",
    ],
)

# Host (macOS) test: run with
# `./build-input/bazel-9.2.0-darwin-arm64 test //submodules/BeyGramMusicFormat:BeyGramMusicFormatTests`.
# Not run yet: no macOS toolchain was available when these tests were written.
swift_test(
    name = "BeyGramMusicFormatTests",
    srcs = [
        "Tests/BGMusicFormatTests.swift",
    ],
    deps = [
        ":BeyGramMusicFormat",
    ],
)
