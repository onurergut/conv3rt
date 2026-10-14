#!/usr/bin/env bash
# Builds one architecture, embeds the universal Sparkle framework, and produces
# a ZIP with a SHA-256 checksum. Set CODESIGN_IDENTITY to a Developer ID
# Application identity for distribution; otherwise signing is ad-hoc.
# Usage: scripts/package.sh [arm64|x86_64] [version] [build-number]
set -euo pipefail

ARCH="${1:-$(uname -m)}"
VERSION="${2:-0.6.0}"
BUILD_NUMBER="${3:-2}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP_NAME="conv3rt"
BUNDLE="$DIST/$APP_NAME.app"
# Override only for local packaging fixtures or an equivalent resolved artifact.
SPARKLE_ROOT="${SPARKLE_ROOT:-$ROOT/.build/artifacts/sparkle/Sparkle}"
SPARKLE_FRAMEWORK="$SPARKLE_ROOT/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
case "$ARCH" in
    arm64) ARCH_NAME=apple-silicon ;;
    x86_64) ARCH_NAME=intel ;;
    *) printf 'Unsupported architecture: %s\n' "$ARCH" >&2; exit 1 ;;
esac
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { printf 'Invalid version: %s\n' "$VERSION" >&2; exit 1; }
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || { printf 'Invalid build number: %s\n' "$BUILD_NUMBER" >&2; exit 1; }
OUTROOT="$DIST/conv3rt-$VERSION-$ARCH_NAME"
ARCHIVE="$OUTROOT/conv3rt-$VERSION-$ARCH_NAME.zip"
KEY_FILE="$ROOT/Resources/update-public-key.txt"
[[ -s "$KEY_FILE" ]] || { printf 'Update public key missing: %s\n' "$KEY_FILE" >&2; exit 1; }
PUBLIC_KEY="$(< "$KEY_FILE")"
[[ "$PUBLIC_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]] || { printf 'Invalid Ed25519 public key: %s\n' "$KEY_FILE" >&2; exit 1; }

printf '==> Building %s for %s (release)...\n' "$APP_NAME" "$ARCH"
cd "$ROOT"
swift build --manifest-cache none -c release --arch "$ARCH"
BIN="$(swift build --manifest-cache none -c release --arch "$ARCH" --show-bin-path)/$APP_NAME"
[[ -x "$BIN" ]] || { printf 'Build did not produce %s\n' "$BIN" >&2; exit 1; }
[[ -d "$SPARKLE_FRAMEWORK" ]] || { printf 'Required Sparkle framework missing: %s\n' "$SPARKLE_FRAMEWORK" >&2; exit 1; }

printf '==> Assembling %s...\n' "$BUNDLE"
rm -rf "$BUNDLE" "$OUTROOT"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources/licenses" "$BUNDLE/Contents/Frameworks"
EXE="$BUNDLE/Contents/MacOS/$APP_NAME"
PLIST="$BUNDLE/Contents/Info.plist"
cp "$BIN" "$EXE"
cp "$ROOT/Resources/Info.plist" "$PLIST"
set_plist() {
    /usr/libexec/PlistBuddy -c "Delete :$1" "$PLIST" > /dev/null 2>&1 || true
    /usr/libexec/PlistBuddy -c "Add :$1 $2 $3" "$PLIST"
}
set_plist CFBundleShortVersionString string "$VERSION"
set_plist CFBundleVersion string "$BUILD_NUMBER"
set_plist SUPublicEDKey string "$PUBLIC_KEY"
set_plist SUFeedURL string "https://raw.githubusercontent.com/onurergut/conv3rt/main/updates/appcast-$ARCH.xml"
for flag in SUAllowsAutomaticUpdates SUAutomaticallyUpdate SUEnableSystemProfiling SUSendProfileInfo; do
    set_plist "$flag" bool false
done
# Leave native second-launch permission handling intact.
/usr/libexec/PlistBuddy -c 'Delete :SUEnableAutomaticChecks' "$PLIST" > /dev/null 2>&1 || true
cp "$ROOT/THIRD_PARTY_NOTICES.txt" "$BUNDLE/Contents/Resources/"
cp "$ROOT/Resources/conv3rt.icns" "$BUNDLE/Contents/Resources/conv3rt.icns"
ditto "$SPARKLE_FRAMEWORK" "$BUNDLE/Contents/Frameworks/Sparkle.framework"
copy_license() {
    [[ -s "$1" ]] || { printf 'Required license missing or empty: %s\n' "$1" >&2; exit 1; }
    cp "$1" "$BUNDLE/Contents/Resources/licenses/$2.txt"
}
copy_license "$SPARKLE_ROOT/LICENSE" Sparkle-LICENSE
copy_license "$ROOT/ThirdParty/libwebp-c/COPYING" libwebp-COPYING
copy_license "$ROOT/ThirdParty/libwebp-c/PATENTS" libwebp-PATENTS
SYMBOLS="$(nm -g "$BIN")"
if [[ "$SYMBOLS" == *"_conv3rt_jxl_encode_rgba"* ]]; then
    copy_license "$ROOT/ThirdParty/jxl-src/LICENSE" libjxl-LICENSE
    copy_license "$ROOT/ThirdParty/jxl-src/PATENTS" libjxl-PATENTS
    copy_license "$ROOT/ThirdParty/jxl-src/third_party/highway/LICENSE" highway-LICENSE
    copy_license "$ROOT/ThirdParty/jxl-src/third_party/brotli/LICENSE" brotli-LICENSE
    copy_license "$ROOT/ThirdParty/jxl-src/third_party/lcms/LICENSE" lcms2-LICENSE
    copy_license "$ROOT/ThirdParty/jxl-src/third_party/libpng/LICENSE" libpng-LICENSE
    copy_license "$ROOT/ThirdParty/jxl-src/third_party/zlib/LICENSE" zlib-LICENSE
fi
if [[ "$SYMBOLS" == *"_conv3rt_avif_encode_rgba"* ]]; then
    DEPS="$ROOT/ThirdParty/avif-build-$ARCH/_deps"
    copy_license "$ROOT/ThirdParty/avif-src/LICENSE" libavif-LICENSE
    copy_license "$DEPS/libaom-src/LICENSE" libaom-LICENSE
    copy_license "$DEPS/libaom-src/PATENTS" libaom-PATENTS
    copy_license "$DEPS/libaom-src/third_party/fastfeat/LICENSE" libaom-fastfeat-LICENSE
    copy_license "$DEPS/libaom-src/third_party/vector/LICENSE" libaom-vector-LICENSE
    copy_license "$DEPS/libaom-src/third_party/x86inc/LICENSE" libaom-x86inc-LICENSE
    copy_license "$DEPS/libyuv-src/LICENSE" libyuv-LICENSE
    copy_license "$DEPS/libyuv-src/PATENTS" libyuv-PATENTS
fi
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

# SwiftPM may add artifact search paths. Remove them from the copy, not the build.
LOAD_COMMANDS="$(otool -l "$EXE")"
RPATHS="$(printf '%s\n' "$LOAD_COMMANDS" | /usr/bin/awk '
    $1 == "cmd" && $2 == "LC_RPATH" { pending=1; next }
    pending && $1 == "path" { sub(/^[[:space:]]*path /, ""); sub(/ \(offset [0-9]+\)$/, ""); print; pending=0 }
' | sort -u)"
while IFS= read -r rpath; do
    case "$rpath" in
        "$ROOT/.build"|"$ROOT/.build/"*|"$SPARKLE_ROOT"|"$SPARKLE_ROOT/"*|*/.build/*|/Applications/*/Contents/Developer/*|/Library/Developer/*)
            install_name_tool -delete_rpath "$rpath" "$EXE" ;;
    esac
done <<< "$RPATHS"

printf '==> Signing...\n'
SIGN_ARGS=(--force --sign "${CODESIGN_IDENTITY:--}")
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    SIGN_ARGS+=(--options runtime --timestamp)
    SIGN_STATE="signed with '$CODESIGN_IDENTITY' (Hardened Runtime). Run scripts/notarize.sh before distributing."
else
    SIGN_STATE='ad-hoc signed (NOT for distribution; set CODESIGN_IDENTITY to sign properly).'
fi
FRAMEWORK="$BUNDLE/Contents/Frameworks/Sparkle.framework"
FRAMEWORK_VERSION="$FRAMEWORK/Versions/B"
for helper in Autoupdate XPCServices/Downloader.xpc XPCServices/Installer.xpc Updater.app; do
    [[ -e "$FRAMEWORK_VERSION/$helper" ]] || { printf 'Required Sparkle helper missing: %s\n' "$helper" >&2; exit 1; }
    codesign "${SIGN_ARGS[@]}" "$FRAMEWORK_VERSION/$helper"
done
codesign "${SIGN_ARGS[@]}" "$FRAMEWORK"
codesign "${SIGN_ARGS[@]}" --entitlements "$ROOT/Resources/conv3rt.entitlements" "$BUNDLE"
codesign --verify --deep --strict --verbose=2 "$BUNDLE"

printf '==> Moving to arch-named folder...\n'
mkdir -p "$OUTROOT"
mv "$BUNDLE" "$OUTROOT/"
CONTENTS="$OUTROOT/$APP_NAME.app"
printf '==> Zipping...\n'
ditto -c -k --keepParent "$CONTENTS" "$ARCHIVE"
DIGEST="$(shasum -a 256 "$ARCHIVE")"
printf '%s\n' "${DIGEST%% *}" > "$ARCHIVE.sha256"
# Apply the same closed-bundle checks used by release verification before success.
bash "$ROOT/scripts/verify-release.sh" "$CONTENTS" "$VERSION" "$ARCH" --development "$BUILD_NUMBER"

APP_SIZE="$(du -sh "$CONTENTS" | /usr/bin/awk '{print $1}')"
ZIP_SIZE="$(du -sh "$ARCHIVE" | /usr/bin/awk '{print $1}')"
BIN_SIZE="$(du -sh "$CONTENTS/Contents/MacOS/$APP_NAME" | /usr/bin/awk '{print $1}')"
printf '\n==================== conv3rt %s (%s), build %s ====================\n' "$VERSION" "$ARCH" "$BUILD_NUMBER"
printf 'Bundle:        %s\nZip:           %s  (%s)\nApp size:      %s\nExecutable:    %s\nSigning:       %s\nChecksum:      %s.sha256\n' \
    "$CONTENTS" "$ARCHIVE" "$ZIP_SIZE" "$APP_SIZE" "$BIN_SIZE" "$SIGN_STATE" "$ARCHIVE"
