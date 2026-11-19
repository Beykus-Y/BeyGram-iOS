load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library", "swift_test")

# BeyGram feature switches, all off by default. Nothing in the app targets depends on this yet.
swift_library(
    name = "BeyGramKit",
    module_name = "BeyGramKit",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# Host (macOS) test. Run with `./build-input/bazel-9.2.0-darwin-arm64 test //submodules/BeyGramKit:BeyGramKitTests`.
swift_test(
    name = "BeyGramKitTests",
    srcs = glob([
        "Tests/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        ":BeyGramKit",
    ],
)
