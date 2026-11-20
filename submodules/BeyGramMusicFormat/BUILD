load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# Pure Foundation model of the .bgmusic v1 snapshot (docs/formats/bgmusic-v1.md in BeyGram),
# text cleaning and track keys (bot:, ym:) shared with the Android build. No Postbox, no UIKit.
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
