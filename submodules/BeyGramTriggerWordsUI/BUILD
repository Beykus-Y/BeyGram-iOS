load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# Settings screen for trigger words. Off by default: the screen is reachable only when the feature flag is on.
swift_library(
    name = "BeyGramTriggerWordsUI",
    module_name = "BeyGramTriggerWordsUI",
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
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/AccountContext:AccountContext",
        "//submodules/BeyGramKit:BeyGramKit",
        "//submodules/BeyGramTriggerWords:BeyGramTriggerWords",
    ],
    visibility = [
        "//visibility:public",
    ],
)
