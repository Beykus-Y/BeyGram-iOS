load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library", "swift_test")

# BeyGram chat export: streaming JSON/HTML writer. Not yet referenced by the app targets.
swift_library(
    name = "BeyGramChatExport",
    module_name = "BeyGramChatExport",
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

# Host (macOS) test. Run with `./build-input/bazel-9.2.0-darwin-arm64 test //submodules/BeyGramChatExport:BeyGramChatExportTests`.
swift_test(
    name = "BeyGramChatExportTests",
    srcs = glob([
        "Tests/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        ":BeyGramChatExport",
    ],
)
