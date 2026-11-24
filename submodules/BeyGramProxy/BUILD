load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("@rules_cc//cc:objc_library.bzl", "objc_library")

filegroup(
    name = "mihomo_core_sources",
    srcs = glob(
        [
            "core/go.mod",
            "core/go.sum",
            "core/bridge/**/*.go",
            "core/cmd/**/*.go",
            "core/normalize/**/*.go",
        ],
        exclude = [
            "core/**/*_test.go",
        ],
    ),
)

genrule(
    name = "beygram_mihomo_archive",
    srcs = [
        "core/build-bazel.sh",
        ":mihomo_core_sources",
    ],
    outs = [
        "libbeygram-mihomo.a",
    ],
    cmd_bash = "bash $(location core/build-bazel.sh) $(TARGET_CPU) $(location libbeygram-mihomo.a)",
    tags = ["no-sandbox"],
)

cc_library(
    name = "beygram_mihomo_core_lib",
    srcs = [
        ":libbeygram-mihomo.a",
    ],
)

objc_library(
    name = "BeyGramMihomoCore",
    module_name = "BeyGramMihomoCore",
    enable_modules = True,
    hdrs = [
        "CoreBridge/include/BeyGramMihomoCore.h",
    ],
    includes = [
        "CoreBridge/include",
    ],
    deps = [
        ":beygram_mihomo_core_lib",
    ],
    sdk_frameworks = [
        "CoreFoundation",
        "Security",
    ],
    sdk_dylibs = [
        "resolv",
    ],
    visibility = [
        "//visibility:public",
    ],
)

swift_library(
    name = "BeyGramProxy",
    module_name = "BeyGramProxy",
    srcs = glob([
        "Sources/**/*.swift",
        "CoreBridge/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        ":BeyGramMihomoCore",
    ],
    visibility = [
        "//visibility:public",
    ],
)
