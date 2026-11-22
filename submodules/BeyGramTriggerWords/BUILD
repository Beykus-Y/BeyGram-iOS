load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library", "swift_test")

# BeyGram trigger words: pure matcher and rule model. Not yet referenced by the app targets.
swift_library(
    name = "BeyGramTriggerWords",
    module_name = "BeyGramTriggerWords",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//third-party/re2:BeyGramRE2",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# Host (macOS) test. Run with `./build-input/bazel-9.2.0-darwin-arm64 test //submodules/BeyGramTriggerWords:BeyGramTriggerWordsTests`.
swift_test(
    name = "BeyGramTriggerWordsTests",
    srcs = glob([
        "Tests/**/*.swift",
    ]),
    # The shared regex parity fixtures (byte-identical to the Android copy), read at run time.
    data = glob([
        "Tests/Fixtures/**",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        ":BeyGramTriggerWords",
    ],
)
