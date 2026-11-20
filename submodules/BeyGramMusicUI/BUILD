load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# BeyGram music screens: the BG Music settings page with the BG Mix and BG Wave entries.
# Every entry is behind a BeyGramFeature flag that is off by default.
swift_library(
    name = "BeyGramMusicUI",
    module_name = "BeyGramMusicUI",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    deps = [
        "//submodules/Display:Display",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/AccountContext:AccountContext",
        "//submodules/BeyGramKit:BeyGramKit",
        "//submodules/BeyGramMedia:BeyGramMedia",
        "//submodules/BeyGramMusicFormat:BeyGramMusicFormat",
    ],
    visibility = [
        "//visibility:public",
    ],
)
