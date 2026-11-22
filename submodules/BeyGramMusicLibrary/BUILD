load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library", "swift_test")

# BeyGram local playlist library for .bgmusic: playlist records, their file store, the import and export layers, and the
# file identifiers that Open in and Share use. Foundation only, on top of BeyGramMusicFormat. No UI here: the music UI
# connects these entry points. Not compiled yet (see CLAUDE.md in this directory).
swift_library(
    name = "BeyGramMusicLibrary",
    module_name = "BeyGramMusicLibrary",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    deps = [
        "//submodules/BeyGramMusicFormat:BeyGramMusicFormat",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# Host (macOS) test: run with
# `./build-input/bazel-9.2.0-darwin-arm64 test //submodules/BeyGramMusicLibrary:BeyGramMusicLibraryTests`.
# Not run yet: no macOS toolchain was available when these tests were written.
swift_test(
    name = "BeyGramMusicLibraryTests",
    srcs = glob([
        "Tests/*.swift",
    ]),
    deps = [
        ":BeyGramMusicLibrary",
        "//submodules/BeyGramMusicFormat:BeyGramMusicFormat",
    ],
)
