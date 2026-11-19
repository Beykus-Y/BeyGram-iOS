load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# Binds BeyGramChatExport to TelegramCore: pages history with message search (empty query) and maps messages.
# Not referenced by app targets until the export screen lands.
swift_library(
    name = "BeyGramChatExportTelegram",
    module_name = "BeyGramChatExportTelegram",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/Postbox:Postbox",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/AccountContext:AccountContext",
        "//submodules/BeyGramChatExport:BeyGramChatExport",
    ],
    visibility = [
        "//visibility:public",
    ],
)
