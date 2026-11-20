load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# Update screen: a manual check and a link to the release page. Behind the updateCheck flag.
swift_library(
    name = "BeyGramUpdatesUI",
    module_name = "BeyGramUpdatesUI",
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
        "//submodules/BeyGramUpdates:BeyGramUpdates",
    ],
    visibility = [
        "//visibility:public",
    ],
)
