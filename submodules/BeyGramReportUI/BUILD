load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# /report screen: description, the nonce from the report bot, and send. Reachable only behind the diagnostics flag.
swift_library(
    name = "BeyGramReportUI",
    module_name = "BeyGramReportUI",
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
        "//submodules/BeyGramDiagnostics:BeyGramDiagnostics",
    ],
    visibility = [
        "//visibility:public",
    ],
)
