#!/usr/bin/env bash
set -euo pipefail

IPA_PATH="${1:?Usage: verify-ipa.sh <path-to-ipa> <expected-bundle-id> <expected-display-name> <expected-version>}"
EXPECTED_BUNDLE_ID="${2:?Missing expected bundle ID}"
EXPECTED_DISPLAY_NAME="${3:?Missing expected display name}"
EXPECTED_VERSION="${4:?Missing expected version}"

if [ ! -f "$IPA_PATH" ]; then
  echo "ERROR: IPA not found at $IPA_PATH"
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

unzip -q "$IPA_PATH" -d "$TMP_DIR"

APP_DIR="$(find "$TMP_DIR/Payload" -maxdepth 1 -name '*.app' -type d | head -n 1)"
if [ -z "$APP_DIR" ] || [ ! -d "$APP_DIR" ]; then
  echo "ERROR: No Payload/*.app found in IPA"
  exit 1
fi
echo "Found app bundle: $(basename "$APP_DIR")"

PLIST="$APP_DIR/Info.plist"
if [ ! -f "$PLIST" ]; then
  echo "ERROR: Info.plist missing in $APP_DIR"
  exit 1
fi

read_plist() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null || true
}

BUNDLE_ID="$(read_plist CFBundleIdentifier)"
DISPLAY_NAME="$(read_plist CFBundleDisplayName)"
BUNDLE_NAME="$(read_plist CFBundleName)"
SHORT_VERSION="$(read_plist CFBundleShortVersionString)"
BUILD_VERSION="$(read_plist CFBundleVersion)"
MIN_OS="$(read_plist MinimumOSVersion)"
EXECUTABLE_NAME="$(read_plist CFBundleExecutable)"

echo "CFBundleIdentifier:         $BUNDLE_ID"
echo "CFBundleDisplayName:        $DISPLAY_NAME"
echo "CFBundleName:               $BUNDLE_NAME"
echo "CFBundleShortVersionString: $SHORT_VERSION"
echo "CFBundleVersion:            $BUILD_VERSION"
echo "MinimumOSVersion:           $MIN_OS"
echo "CFBundleExecutable:         $EXECUTABLE_NAME"

[ "$BUNDLE_ID" = "$EXPECTED_BUNDLE_ID" ] || { echo "ERROR: Bundle ID mismatch (expected $EXPECTED_BUNDLE_ID, got $BUNDLE_ID)"; exit 1; }
[ "$DISPLAY_NAME" = "$EXPECTED_DISPLAY_NAME" ] || { echo "ERROR: Display Name mismatch (expected $EXPECTED_DISPLAY_NAME, got $DISPLAY_NAME)"; exit 1; }
[ "$SHORT_VERSION" = "$EXPECTED_VERSION" ] || { echo "ERROR: Version mismatch (expected $EXPECTED_VERSION, got $SHORT_VERSION)"; exit 1; }
[ -n "$MIN_OS" ] || { echo "ERROR: MinimumOSVersion is empty"; exit 1; }

EXEC_PATH="$APP_DIR/$EXECUTABLE_NAME"
if [ ! -f "$EXEC_PATH" ]; then
  echo "ERROR: Executable not found at $EXEC_PATH"
  exit 1
fi

ARCH_INFO="$(lipo -info "$EXEC_PATH")"
echo "Executable architectures:   $ARCH_INFO"
if ! echo "$ARCH_INFO" | grep -q "arm64"; then
  echo "ERROR: Executable is not arm64"
  exit 1
fi
if echo "$ARCH_INFO" | grep -qE "x86_64|i386"; then
  echo "ERROR: Simulator/x86 architecture found in executable"
  exit 1
fi

OTOOL_OUT="$(otool -l "$EXEC_PATH" | grep -A 3 "LC_BUILD_VERSION" || true)"
if echo "$OTOOL_OUT" | grep -q "IOSSIMULATOR"; then
  echo "ERROR: Executable was built for iOS Simulator"
  exit 1
fi

# Verify URL schemes
URL_SCHEMES="$(plutil -convert json -o - "$PLIST" | python3 -c '
import json, sys
d = json.load(sys.stdin)
schemes = []
for item in d.get("CFBundleURLTypes", []):
    schemes.extend(item.get("CFBundleURLSchemes", []))
print(" ".join(schemes))
')"
echo "URL Schemes:                $URL_SCHEMES"
if ! echo "$URL_SCHEMES" | grep -qw "beygram"; then
  echo "ERROR: beygram URL scheme is missing"
  exit 1
fi
for forbidden in tg telegram ton tonsite tc; do
  if echo "$URL_SCHEMES" | grep -qw "$forbidden"; then
    echo "ERROR: Forbidden official URL scheme '$forbidden' found in Info.plist"
    exit 1
  fi
done

# Verify no official Telegram identifiers in Info.plist
if plutil -convert xml1 -o - "$PLIST" | grep -qE "ph\.telegra\.Telegraph|org\.telegram\.Telegram-iOS"; then
  echo "ERROR: Official Telegram bundle ID found in Info.plist"
  exit 1
fi

# Verify extensions (sideload build expects none, or matching prefix)
if [ -d "$APP_DIR/PlugIns" ]; then
  echo "Checking embedded extensions in PlugIns/..."
  for ext in "$APP_DIR/PlugIns"/*.appex; do
    [ -e "$ext" ] || continue
    ext_id="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$ext/Info.plist")"
    echo "  Extension: $(basename "$ext") -> $ext_id"
    case "$ext_id" in
      "$EXPECTED_BUNDLE_ID".*) ;;
      *) echo "ERROR: Extension $ext_id does not match $EXPECTED_BUNDLE_ID.*"; exit 1 ;;
    esac
  done
else
  echo "Embedded extensions:        None (sideload-optimized)"
fi

# Verify no accidental certificates or private keys
BAD_FILES="$(find "$APP_DIR" -type f \( -name "*.p12" -o -name "*.cer" -o -name "*.pem" -o -name "*.key" \))"
if [ -n "$BAD_FILES" ]; then
  echo "ERROR: Found unexpected certificate/key files in app bundle:"
  echo "$BAD_FILES"
  exit 1
fi

# Print entitlements if present
codesign -d --entitlements - "$APP_DIR" 2>/dev/null || echo "Entitlements:               (unsigned / ad-hoc)"
echo "IPA verification PASSED!"
