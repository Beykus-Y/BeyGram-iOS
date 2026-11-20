"""Selects the host-matching WASI SDK repository for WebAssembly builds."""

def _wasi_sdk_host_impl(repository_ctx):
    os_name = repository_ctx.os.name.lower()
    arch = repository_ctx.os.arch.lower()
    is_arm64 = arch in ["arm64", "aarch64"]
    is_x86_64 = arch in ["x86_64", "amd64"]

    if "mac" in os_name or "darwin" in os_name:
        if is_arm64:
            target_repo = "@wasi_sdk_macos_arm64"
        elif is_x86_64:
            target_repo = "@wasi_sdk_macos_x86_64"
        else:
            fail("Unsupported macOS host architecture for WASI SDK: {}".format(arch))
    elif "linux" in os_name:
        if is_arm64:
            target_repo = "@wasi_sdk_linux_arm64"
        elif is_x86_64:
            target_repo = "@wasi_sdk_linux_x86_64"
        else:
            fail("Unsupported Linux host architecture for WASI SDK: {}".format(arch))
    else:
        fail("Unsupported host OS for WASI SDK: {}".format(os_name))

    repository_ctx.file("BUILD.bazel", """
alias(
    name = "bin/clang++",
    actual = "{repo}//:bin/clang++",
    visibility = ["//visibility:public"],
)

alias(
    name = "all_files",
    actual = "{repo}//:all_files",
    visibility = ["//visibility:public"],
)
""".format(repo = target_repo))

wasi_sdk_host = repository_rule(
    implementation = _wasi_sdk_host_impl,
    local = True,
)

