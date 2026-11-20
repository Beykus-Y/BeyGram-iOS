load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# Feeds the account's new incoming messages to the trigger-word ingestor, reads the preview settings,
# and posts local alerts. Behind the triggerWords flag.
swift_library(
    name = "BeyGramTriggerWordsTelegram",
    module_name = "BeyGramTriggerWordsTelegram",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/AccountContext:AccountContext",
        "//submodules/BeyGramKit:BeyGramKit",
        "//submodules/BeyGramTriggerWords:BeyGramTriggerWords",
    ],
    visibility = [
        "//visibility:public",
    ],
)
