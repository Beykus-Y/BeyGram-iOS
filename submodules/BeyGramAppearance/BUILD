load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library", "swift_test")

# The BeyGram visual style axis (Telegram Original + 5 BeyGram Android styles).
# Independent of PresentationTheme colours; supplies geometry, surface treatment, and motion tokens.
swift_library(
    name = "BeyGramAppearance",
    module_name = "BeyGramAppearance",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
    ],
    visibility = [
        "//visibility:public",
    ],
)

swift_test(
    name = "BeyGramAppearanceTests",
    srcs = glob([
        "Tests/**/*.swift",
    ]),
    deps = [
        ":BeyGramAppearance",
    ],
)
