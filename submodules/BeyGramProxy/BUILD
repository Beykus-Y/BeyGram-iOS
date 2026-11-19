load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "BeyGramProxy",
    module_name = "BeyGramProxy",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    sdk_frameworks = [
        "Security",
    ],
    deps = [],
    visibility = [
        "//visibility:public",
    ],
)
