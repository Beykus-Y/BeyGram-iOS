load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library", "swift_test")

# BeyGram bug report model and upload request builder. Not yet referenced by the app targets.
swift_library(
    name = "BeyGramDiagnostics",
    module_name = "BeyGramDiagnostics",
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

# Host (macOS) test. Run with `./build-input/bazel-9.2.0-darwin-arm64 test //submodules/BeyGramDiagnostics:BeyGramDiagnosticsTests`.
swift_test(
    name = "BeyGramDiagnosticsTests",
    srcs = glob([
        "Tests/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        ":BeyGramDiagnostics",
    ],
)
