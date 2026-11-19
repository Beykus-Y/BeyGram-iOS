load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# Chat export screen: format, folder picker, progress and cancel. Reachable only from a hook behind the flag.
swift_library(
    name = "BeyGramChatExportUI",
    module_name = "BeyGramChatExportUI",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/Display:Display",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/Postbox:Postbox",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/AccountContext:AccountContext",
        "//submodules/BeyGramChatExport:BeyGramChatExport",
        "//submodules/BeyGramChatExportTelegram:BeyGramChatExportTelegram",
    ],
    visibility = [
        "//visibility:public",
    ],
)
