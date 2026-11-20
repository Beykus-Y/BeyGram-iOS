#!/bin/sh
# This file is part of BeyGram and is distributed under the GNU General Public License v3.0.
# See submodules/BeyGramProxy/LICENSE and the NOTICE file at the repository root.
#
# Builds libbeygram-mihomo.a for the iOS device (arm64). Needs macOS with Xcode, its iphoneos SDK and Go 1.24.
# Not run by Bazel or CI. The output goes to submodules/BeyGramProxy/CoreBridge/lib (ignored by git).
# Not verified on a Mac yet; see submodules/BeyGramProxy/README.md.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$HERE/../CoreBridge/lib}"
MIN_IOS="${MIN_IOS:-15.0}"   # set to the app's deployment target before shipping

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CC="$(xcrun --sdk iphoneos --find clang)"
FLAGS="-isysroot $SDK -arch arm64 -miphoneos-version-min=$MIN_IOS"

mkdir -p "$OUT"
cd "$HERE"
GOOS=ios GOARCH=arm64 CGO_ENABLED=1 CC="$CC" \
CGO_CFLAGS="$FLAGS" CGO_LDFLAGS="$FLAGS" \
go build -trimpath -buildmode=c-archive -ldflags="-s -w" \
  -o "$OUT/libbeygram-mihomo.a" ./cmd/beygram-mihomo

# go writes libbeygram-mihomo.h next to the archive. The app uses the hand-written header in CoreBridge/include,
# which must declare the same two functions. Check it:
nm "$OUT/libbeygram-mihomo.a" | grep -E ' T _?BGMihomo(Invoke|Free)$'
ls -la "$OUT/libbeygram-mihomo.a"
