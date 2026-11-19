load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# The BeyGram visual style axis (Telegram / BeyGram). It holds the style choice and the geometry tokens only;
# colours always come from the active PresentationTheme, so every Telegram theme works with both styles.
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
