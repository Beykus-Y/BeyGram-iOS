# libdatachannel for BG Wave (iOS)

Vendored sources for BG Wave's P2P transport on iOS. Android builds the same versions through BG-Media's
`cmake/FindOrFetchLibDataChannel.cmake`, so both platforms run one stack and one wire behaviour. Bazel builds
`BUILD` here; there is no CMake on iOS.

Status of this copy: **written and statically checked; not built for iOS yet.** The verification ledger is in
`docs/bg-wave-ios.md`.

## Pins

| Component | Version | Upstream commit | Vendored under | License |
|---|---|---|---|---|
| libdatachannel | v0.22.5 | `988e3f3a8e018711e3fc6d9500344d35b8a45a8d` | `src/`, `include/` | MPL-2.0 (`LICENSE.libdatachannel`) |
| libjuice | v1.5.9 | `8d1a99a0683a811876c03a73ff764a92774027ad` | `libjuice/src`, `libjuice/include` | MPL-2.0 (`libjuice/LICENSE`) |
| usrsctp | `ebb18adac6501bad4501b1f6dccb67a1c85cc299` | same | `usrsctp/usrsctplib/` | BSD-3-Clause (`usrsctp/LICENSE.md`) |
| plog | `e21baecd4753f14da64ede979c5a19302618b752` | same | `plog/include/` | MIT (`plog/LICENSE`) |

These are the commits libdatachannel v0.22.5's `.gitmodules` and BG-Media's FetchContent use. No file is changed
from upstream: `diff -rq` against the tree that the Linux build used shows no differences. Files that the build does not
compile (tests, examples, docs, Windows and Nettle code paths) are not copied.

Licence check (an engineering record, not a legal opinion): the MPL-2.0 files keep their licence inside the app, which is GPL-2.0-or-later. No source file in this tree carries the MPL-2.0 notice "Incompatible With Secondary Licenses", and none carries the MPL-2.0 Exhibit A notice either, so the MPL terms reach these files through the LICENSE files. The attribution and the reading are in the root NOTICE. MPL-2.0 is
a secondary licence compatible with GPL-2.0 or later. Whether the combined build may be distributed is the owner's decision.

## What is not vendored, and why

- **libsrtp.** The app already links WebRTC's copy, `//third-party/webrtc/libsrtp:libsrtp` (BoringSSL-based). Two
  copies would both define `srtp_*` in one binary. The BUILD takes the header from `//third-party/webrtc/libsrtp:srtp_public`,
  which is a new header-only target in that package and depends on the same `:libsrtp`.
- **OpenSSL.** The BUILD uses BoringSSL, `//third-party/boringssl:ssl` and `:crypto`, the same as WebRTC and TDLib
  (`third-party/td/BUILD` already gives TDLib BoringSSL's `crypto` as its OpenSSL). BoringSSL reports
  `OPENSSL_VERSION_NUMBER 0x1010107f`, so libdatachannel's OpenSSL-3-only branches (`EVP_EC_gen`, `EVP_RSA_gen`) are not
  compiled. The OpenSSL identifiers that libdatachannel still uses were checked against the repo's BoringSSL headers.
- **WebSocket** (`RTC_ENABLE_WEBSOCKET=0`) and **nlohmann/json**. The sources of the WebSocket files stay in the list:
  they compile to nothing with the flag off, as in the Linux build.

## Symbol policy

- **Namespace.** libdatachannel's API is `namespace rtc`, and WebRTC's `rtc_base` uses `rtc::` too. In one binary the
  two would define the same mangled names with different layouts, and the linker reports no error for inline or weak
  symbols. The library is compiled with `-Drtc=bgrtc`, and the define goes to consumers through `defines`. BG-Media's
  `adapters/wave_webrtc` (`WebRtcWaveTransport.cpp`, 57 uses of `rtc::`) is renamed with it.
  Checked: libdatachannel has no identifier named `rtc` apart from the namespace (the other hits are a string literal and
  a comment).
- **Crypto.** One BoringSSL. No `OPENSSL_*` prefix or second TLS library.
- **Opus.** `//third-party/opus:opus`, the same libopus that WebRTC's targets already depend on.
- **usrsctp, libjuice, plog.** WebRTC's tree holds a usrsctp copy under `third-party/webrtc/dependencies/third_party/usrsctp`, which WebRTC's GN build uses. No Bazel BUILD file refers to that copy, so Bazel links only this one. The Bazel build of WebRTC uses dcsctp for SCTP. libjuice uses its own
  hash code (`USE_NETTLE=0`), so it needs no TLS library.

## App rules that follow from the shared libsrtp

- **Never call `rtc::Cleanup()`.** It ends in `DtlsSrtpTransport::Cleanup()`, which calls `srtp_shutdown()` on the libsrtp
  copy that WebRTC calls use. `rtc::Preload()` is safe.
- **`srtp_init()` may run more than once.** libdatachannel calls it from `Init`, and WebRTC's libsrtp returns its
  self-test status when it is already initialised (`crypto/kernel/crypto_kernel.c`), so a second call is harmless.

## Linux evidence for this copy

Built on Linux (g++ 13, Debug) from the BG-Media dev pin `74d309d`, with libdatachannel from this tree's commit:

| Configuration | `wave.` | `wave_real.` |
|---|---|---|
| OpenSSL 3.0.13 (system), libsrtp bundled in libdatachannel | 20 of 20 | 9 of 9 |
| BoringSSL from `third-party/boringssl`, libsrtp bundled | 20 of 20 | 9 of 9 |
| BoringSSL, `rtc` → `bgrtc` rename, libsrtp bundled | 20 of 20 | 9 of 9 |
| BoringSSL, `rtc` → `bgrtc`, WebRTC's libsrtp copy (the iOS choice) | 20 of 20 | 9 of 9 |

The BoringSSL row needed a scratch-only `opensslv.h` in front of the repo's BoringSSL headers, because CMake's
`FindOpenSSL` reads the version from that file. The file is not in the repo. Under the rename the peer binary contains
12025 `bgrtc::` symbols and no `rtc::` symbol. The `wave_real` set includes an in-process DTLS-SRTP call with Opus and
a tampered fingerprint check, so both use the BoringSSL DTLS path.

The last row is the configuration the iOS app will link. Its libsrtp is built from
`third-party/webrtc/libsrtp/third_party/libsrtp` (17 files, with the config defines of `libsrtp_config`), the same file list as
`//third-party/webrtc/libsrtp:libsrtp`. The Linux build of that copy is scratch-only, because there is no Bazel on Linux here.
WebRTC calls and BG Wave then share one copy of the SRTP code, which is the design goal of this row.

Syntax check with the BUILD's flags, Linux: all 58 libdatachannel C++ files against the repo's BoringSSL and libsrtp
headers, all 20 libjuice C files, and all 23 usrsctp C files with Linux flags (the Darwin flags can only be checked on a
Mac).

## Files

- `BUILD`: Bazel targets `plog`, `libjuice`, `usrsctp`, `libdatachannel`. The source lists come from the Linux build
  graph (`ninja -t commands`), so each file in them is one that build compiles.
- `src/`, `include/`, `libjuice/`, `usrsctp/`, `plog/`: the vendored sources.
