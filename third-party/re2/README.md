# RE2 (vendored)

Vendored [google/re2](https://github.com/google/re2) for the BeyGram trigger words, regex mode.

| | |
|---|---|
| Upstream | https://github.com/google/re2 |
| Tag | `2025-11-05` |
| Commit | `927f5d53caf8111721e734cf24724686bb745f55` |
| License | BSD-3-Clause. `LICENSE` is copied from the upstream root, unchanged. |

## What is here

- `re2/`, `util/`: the sources and headers from the tag, unchanged. The source list is `re2_sources` in `BUILD.bazel`. Tests, benchmarks, `re2/testing`, and the Python, Go, Java, CMake and Makefile builds are not vendored.
- `bridge/bgre2.h`, `bridge/bgre2.cc`: a C interface, so Swift never sees a C++ type.
  - `bgre2_compile` compiles a UTF-8 pattern once, when a rule is created or changed. It returns NULL when RE2 rejects the pattern.
  - `bgre2_partial_match` runs an unanchored search, as `java.util.regex.Matcher.find` does. Captures are off and RE2's own error log is off.
  - `bgre2_free` releases the handle.
- `tests/linux_check.py`: builds RE2, the Abseil sources and the bridge into a shared library on Linux, then runs `submodules/BeyGramTriggerWords/Tests/Fixtures/regex_parity.json` through the C ABI. It needs only clang++ and Python 3.

## Abseil

RE2 uses Abseil (`absl::Mutex`, `absl/log`, and the rest). The app already compiles Abseil in `third-party/webrtc/absl` (LTS 20300401). The bridge reuses that copy; no second copy is added.

- `//third-party/webrtc/absl:absl` is unchanged. It provides the sources WebRTC needs.
- `//third-party/webrtc/absl:absl_re2` adds the 41 sources RE2 needs on top of it: the log, Cord, CRC, hash, flags and status pieces, `absl::Mutex`, and the platform waiters and CRC variants. Each platform file is empty unless its own `ABSL_INTERNAL_HAVE_*` macro selects it, so the iOS build gets the right one.
- The list was found by linking RE2 and the bridge against the Abseil sources on Linux, with `-Wl,--no-undefined`. RE2 2025-11-05 was written against Abseil 20250512.1; it compiles and links against the LTS copy with the same API.

## Android parity

Android matches with RE2/J 1.7, the Java port, using `Matcher.find`. The shared fixtures pin the cases both engines must agree on, for example:

- `\bпривет\b` does not fire on `привет всем`: `\w`, `\d`, `\s` and `\b` are ASCII-only in RE2.
- Case folding follows the flag, not the text: `Deadline` with `ignoreCase` matches `DEADLINE`, and without it does not.

Differences the fixtures do not cover, to check before the regex mode ships: RE2 rejects repetition counts above 1000 and the `\C` escape, and RE2/J's limits may differ.

## Checks

- Linux: `python3 third-party/re2/tests/linux_check.py`. It builds all 166 sources, with the bridge under `-Wall -Wextra -Werror`, and runs the 17 fixture cases.
- Not run here: the Bazel build, the Swift tests, and the Darwin link. Those need a Mac.

## Updating RE2

1. Replace `re2/`, `util/` and `LICENSE` from the new tag, and update the commit and tag above.
2. Update `re2_sources` in `BUILD.bazel` to match the `.cc` files of the tag, excluding tests and benchmarks.
3. Run `python3 third-party/re2/tests/linux_check.py`. A new undefined Abseil symbol shows up there; add the file that defines it to `absl_re2_sources`.
