load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library", "swift_test")

# Yandex Music as a second music source. Off by default: it needs the `yandexMusic` flag, the OAuth pair
# (empty here, so the source stays hidden), and the user's accepted warning. Pure Foundation; no UI.
swift_library(
    name = "BeyGramYandexMusic",
    module_name = "BeyGramYandexMusic",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    deps = [],
    visibility = [
        "//visibility:public",
    ],
)

# Host (macOS) test, not run yet: `./build-input/bazel-9.2.0-darwin-arm64 test //submodules/BeyGramYandexMusic:BeyGramYandexMusicTests`.
swift_test(
    name = "BeyGramYandexMusicTests",
    srcs = [
        "Tests/BGYandexTests.swift",
        "Tests/BGYandexAudioCheckTests.swift",
    ],
    data = ["Tests/Fixtures/synthetic-tone.mp3"],
    linkopts = ["-framework", "AVFoundation"],
    deps = [
        ":BeyGramYandexMusic",
    ],
)
