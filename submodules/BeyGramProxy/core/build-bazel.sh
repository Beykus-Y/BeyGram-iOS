#!/bin/sh
# This file is part of BeyGram and is distributed under the GNU General Public License v3.0.
# See submodules/BeyGramProxy/LICENSE and the NOTICE file at the repository root.
#
# Builds libbeygram-mihomo.a for Bazel from core/cmd/beygram-mihomo.
# Arguments: <TARGET_CPU> <OUTPUT_ARCHIVE_PATH>
set -eu

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <TARGET_CPU> <OUTPUT_ARCHIVE_PATH>" >&2
    exit 1
fi

TARGET_CPU="$1"
OUT_PATH="$2"
MIN_IOS="${MIN_IOS:-15.0}"
MIN_MACOS="${MIN_MACOS:-15.0}"

CORE_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$(cd "$(dirname "$OUT_PATH")" && pwd)"
OUT_ABS="$OUT_DIR/$(basename "$OUT_PATH")"

find_go() {
    if command -v go >/dev/null 2>&1; then
        command -v go
        return 0
    fi
    for candidate in \
        /opt/local/bin/go \
        /usr/local/go/bin/go \
        /opt/homebrew/bin/go \
        /usr/local/bin/go \
        "${HOME:-}/go/bin/go"; do
        if [ -x "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

GO_BIN="$(find_go || true)"
if [ -z "$GO_BIN" ]; then
    echo "error: Go compiler not found (need Go >= 1.24.7). Install Go or add it to PATH." >&2
    exit 1
fi

case "$TARGET_CPU" in
    ios_arm64)
        GOOS="ios"
        GOARCH="arm64"
        SDK="iphoneos"
        ARCH_FLAGS="-arch arm64 -miphoneos-version-min=$MIN_IOS"
        ;;
    ios_sim_arm64)
        GOOS="ios"
        GOARCH="arm64"
        SDK="iphonesimulator"
        ARCH_FLAGS="-arch arm64 -mios-simulator-version-min=$MIN_IOS"
        ;;
    ios_x86_64)
        GOOS="ios"
        GOARCH="amd64"
        SDK="iphonesimulator"
        ARCH_FLAGS="-arch x86_64 -mios-simulator-version-min=$MIN_IOS"
        ;;
    darwin_arm64)
        GOOS="darwin"
        GOARCH="arm64"
        SDK="macosx"
        ARCH_FLAGS="-arch arm64 -mmacosx-version-min=$MIN_MACOS"
        ;;
    darwin_x86_64)
        GOOS="darwin"
        GOARCH="amd64"
        SDK="macosx"
        ARCH_FLAGS="-arch x86_64 -mmacosx-version-min=$MIN_MACOS"
        ;;
    *)
        echo "error: unsupported TARGET_CPU '$TARGET_CPU' for BeyGramMihomoCore" >&2
        exit 1
        ;;
esac

SDK_PATH="$(xcrun --sdk "$SDK" --show-sdk-path)"
CC="$(xcrun --sdk "$SDK" --find clang)"
FLAGS="-isysroot $SDK_PATH $ARCH_FLAGS"

if [ -z "${HOME:-}" ]; then
    HOME="$(dscl . -read "/Users/$(id -un)" NFSHomeDirectory 2>/dev/null | awk '{print $2}' || echo "${TMPDIR:-/tmp}")"
    export HOME
fi

TMP_OUT="$OUT_DIR/beygram-mihomo-${TARGET_CPU}.a"
TMP_HDR="$OUT_DIR/beygram-mihomo-${TARGET_CPU}.h"
rm -f "$TMP_OUT" "$TMP_HDR"

cd "$CORE_DIR"
GOOS="$GOOS" GOARCH="$GOARCH" CGO_ENABLED=1 CC="$CC" \
CGO_CFLAGS="$FLAGS" CGO_LDFLAGS="$FLAGS" \
"$GO_BIN" build -trimpath -buildmode=c-archive -ldflags="-s -w" \
    -o "$TMP_OUT" ./cmd/beygram-mihomo

rm -f "$TMP_HDR"

if ! nm "$TMP_OUT" | grep -qE ' T _?BGMihomoInvoke$'; then
    echo "error: BGMihomoInvoke symbol missing from $TMP_OUT" >&2
    exit 1
fi
if ! nm "$TMP_OUT" | grep -qE ' T _?BGMihomoFree$'; then
    echo "error: BGMihomoFree symbol missing from $TMP_OUT" >&2
    exit 1
fi

mv -f "$TMP_OUT" "$OUT_ABS"
