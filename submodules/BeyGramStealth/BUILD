load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library", "swift_test")

# BeyGram privacy and stealth (block B of the iOS plan): per-account settings, decisions and the hooks that TelegramCore
# calls. Depends on Foundation and BeyGramKit only, never on Postbox or TelegramCore.
swift_library(
    name = "BeyGramStealth",
    module_name = "BeyGramStealth",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/BeyGramKit:BeyGramKit",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# Host (macOS) test: pure logic, no app bundle.
# Run with `./build-input/bazel-9.2.0-darwin-arm64 test //submodules/BeyGramStealth:BeyGramStealthTests`.
swift_test(
    name = "BeyGramStealthTests",
    srcs = [
        "Tests/BeyGramStealthDelayedSendTests.swift",
        "Tests/BeyGramStealthTests.swift",
    ],
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        ":BeyGramStealth",
    ],
)
