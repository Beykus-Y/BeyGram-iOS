load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "BeyGramDesign",
    module_name = "BeyGramDesign",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/Display:Display",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/AccountContext:AccountContext",
        "//submodules/BeyGramAppearance:BeyGramAppearance",
        "//submodules/BeyGramKit:BeyGramKit",
    ],
    visibility = [
        "//visibility:public",
    ],
)
