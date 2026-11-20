load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library", "swift_test")

# Manual update check for BeyGram Stable (contract: docs/stable-updates.md). Logic only: no installs on iOS.
swift_library(
    name = "BeyGramUpdates",
    module_name = "BeyGramUpdates",
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

# Host (macOS) test. Run with `./build-input/bazel-9.2.0-darwin-arm64 test //submodules/BeyGramUpdates:BeyGramUpdatesTests`.
swift_test(
    name = "BeyGramUpdatesTests",
    srcs = glob([
        "Tests/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        ":BeyGramUpdates",
    ],
)
