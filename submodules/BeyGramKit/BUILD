load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library", "swift_test")

swift_library(
    name = "BeyGramKit",
    module_name = "BeyGramKit",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [],
    visibility = [
        "//visibility:public",
    ],
)

swift_test(
    name = "BeyGramKitTests",
    srcs = glob([
        "Tests/**/*.swift",
    ]),
    deps = [
        ":BeyGramKit",
    ],
)
