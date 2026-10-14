#!/usr/bin/env bash
set -euo pipefail

APP="${1:?usage: verify-release.sh <app> <version> <arm64|x86_64> [--development]}"
VERSION="${2:?version required}"
ARCH="${3:?architecture required}"
MODE="${4:-release}"
case "$ARCH" in
    arm64) ARCH_NAME=apple-silicon ;;
    x86_64) ARCH_NAME=intel ;;
    *) printf 'Unsupported architecture: %s\n' "$ARCH" >&2; exit 1 ;;
esac
case "$MODE" in
    release|--development) ;;
    *) printf 'Unknown verification mode: %s\n' "$MODE" >&2; exit 1 ;;
esac
PARENT="$(cd "$(dirname "$APP")" && pwd)"
APP="$PARENT/$(basename "$APP")"
ARCHIVE="$PARENT/conv3rt-$VERSION-$ARCH_NAME.zip"
PLIST="$APP/Contents/Info.plist"
BIN="$APP/Contents/MacOS/conv3rt"

fail() { printf '%s\n' "$*" >&2; exit 1; }
require_file() { [[ -s "$1" ]] || fail "Missing or empty: $1"; }
require_file "$PLIST"
[[ -x "$BIN" ]] || fail "Missing executable: $BIN"
ACTUAL_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
[[ "$ACTUAL_VERSION" == "$VERSION" ]] || fail "Version mismatch: expected $VERSION, found $ACTUAL_VERSION"
[[ "$(lipo -archs "$BIN")" == "$ARCH" ]] || fail "Executable architecture differs from $ARCH"
codesign --verify --deep --strict --verbose=2 "$APP"
require_file "$APP/Contents/Resources/THIRD_PARTY_NOTICES.txt"
require_file "$APP/Contents/Resources/conv3rt.icns"

licenses=(libwebp-COPYING libwebp-PATENTS)
SYMBOLS="$(nm -g "$BIN")"
if [[ "$SYMBOLS" == *"_conv3rt_jxl_encode_rgba"* ]]; then
    licenses+=(libjxl-LICENSE libjxl-PATENTS highway-LICENSE brotli-LICENSE lcms2-LICENSE libpng-LICENSE zlib-LICENSE)
fi
if [[ "$SYMBOLS" == *"_conv3rt_avif_encode_rgba"* ]]; then
    licenses+=(libavif-LICENSE libaom-LICENSE libaom-PATENTS libaom-fastfeat-LICENSE libaom-vector-LICENSE libaom-x86inc-LICENSE libyuv-LICENSE libyuv-PATENTS)
fi
for license in "${licenses[@]}"; do
    require_file "$APP/Contents/Resources/licenses/$license.txt"
done
"$BIN" --dump-capabilities > /dev/null
require_file "$ARCHIVE"
require_file "$ARCHIVE.sha256"
DIGEST="$(shasum -a 256 "$ARCHIVE")"
[[ "$(< "$ARCHIVE.sha256")" == "${DIGEST%% *}" ]] || fail 'Archive SHA-256 mismatch'

TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
ditto -x -k "$ARCHIVE" "$TEMP"
ARCHIVED_APP="$TEMP/conv3rt.app"
ARCHIVED_BIN="$ARCHIVED_APP/Contents/MacOS/conv3rt"
require_file "$ARCHIVED_APP/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ARCHIVED_APP/Contents/Info.plist")" == "$VERSION" ]] || fail 'Archive version mismatch'
[[ "$(lipo -archs "$ARCHIVED_BIN")" == "$ARCH" ]] || fail 'Archive architecture mismatch'
cmp "$PLIST" "$ARCHIVED_APP/Contents/Info.plist" || fail 'Archive Info.plist differs from bundle'
cmp "$BIN" "$ARCHIVED_BIN" || fail 'Archive executable differs from bundle'
codesign --verify --deep --strict --verbose=2 "$ARCHIVED_APP"
require_file "$ARCHIVED_APP/Contents/Resources/THIRD_PARTY_NOTICES.txt"
require_file "$ARCHIVED_APP/Contents/Resources/conv3rt.icns"
for license in "${licenses[@]}"; do
    require_file "$ARCHIVED_APP/Contents/Resources/licenses/$license.txt"
done

if [[ "$MODE" == release ]]; then
    xcrun stapler validate "$ARCHIVED_APP"
    spctl -a -vvv -t exec "$ARCHIVED_APP"
    xcrun stapler validate "$APP"
    spctl -a -vvv -t exec "$APP"
    printf 'Release verification passed: %s\n' "$ARCHIVE"
else
    printf 'Development package verified; notarization and Gatekeeper not checked: %s\n' "$ARCHIVE"
fi
