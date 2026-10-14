#!/usr/bin/env bash
# Builds a conv3rt.app for one architecture and packages it as a .zip with a
# SHA-256 checksum. Signing is optional: set CODESIGN_IDENTITY to a "Developer
# ID Application" identity to sign; otherwise the app is left unsigned and
# clearly labelled as such.
#
# Usage: scripts/package.sh [arm64|x86_64] [version]
set -euo pipefail

ARCH="${1:-$(uname -m)}"
VERSION="${2:-0.1.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP_NAME="conv3rt"
BUNDLE="$DIST/$APP_NAME.app"
case "$ARCH" in
    arm64) ARCH_NAME=apple-silicon ;;
    x86_64) ARCH_NAME=intel ;;
    *) printf 'Unsupported architecture: %s\n' "$ARCH" >&2; exit 1 ;;
esac
OUTROOT="$DIST/conv3rt-$VERSION-$ARCH_NAME"
ARCHIVE="$OUTROOT/conv3rt-$VERSION-$ARCH_NAME.zip"

echo "==> Building $APP_NAME for $ARCH (release)..."
cd "$ROOT"
swift build --manifest-cache none -c release --arch "$ARCH"
BIN="$(swift build --manifest-cache none -c release --arch "$ARCH" --show-bin-path)/$APP_NAME"
[ -x "$BIN" ] || { echo "build did not produce $BIN"; exit 1; }

echo "==> Assembling $BUNDLE..."
rm -rf "$BUNDLE" "$OUTROOT"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN" "$BUNDLE/Contents/MacOS/$APP_NAME"
sed "s/0\.1\.0/$VERSION/g" "$ROOT/Resources/Info.plist" > "$BUNDLE/Contents/Info.plist"
cp "$ROOT/THIRD_PARTY_NOTICES.txt" "$BUNDLE/Contents/Resources/"
cp "$ROOT/Resources/conv3rt.icns" "$BUNDLE/Contents/Resources/conv3rt.icns"
mkdir -p "$BUNDLE/Contents/Resources/licenses"
copy_license() {
    local source="$ROOT/$1"
    [[ -s "$source" ]] || { printf 'Required license missing or empty: %s\n' "$source" >&2; exit 1; }
    cp "$source" "$BUNDLE/Contents/Resources/licenses/$2.txt"
}
copy_license ThirdParty/libwebp-c/COPYING libwebp-COPYING
copy_license ThirdParty/libwebp-c/PATENTS libwebp-PATENTS
SYMBOLS="$(nm -g "$BIN")"
if [[ "$SYMBOLS" == *"_conv3rt_jxl_encode_rgba"* ]]; then
    copy_license ThirdParty/jxl-src/LICENSE libjxl-LICENSE
    copy_license ThirdParty/jxl-src/PATENTS libjxl-PATENTS
    copy_license ThirdParty/jxl-src/third_party/highway/LICENSE highway-LICENSE
    copy_license ThirdParty/jxl-src/third_party/brotli/LICENSE brotli-LICENSE
    copy_license ThirdParty/jxl-src/third_party/lcms/LICENSE lcms2-LICENSE
    copy_license ThirdParty/jxl-src/third_party/libpng/LICENSE libpng-LICENSE
    copy_license ThirdParty/jxl-src/third_party/zlib/LICENSE zlib-LICENSE
fi
if [[ "$SYMBOLS" == *"_conv3rt_avif_encode_rgba"* ]]; then
    DEPS="ThirdParty/avif-build-$ARCH/_deps"
    copy_license ThirdParty/avif-src/LICENSE libavif-LICENSE
    copy_license "$DEPS/libaom-src/LICENSE" libaom-LICENSE
    copy_license "$DEPS/libaom-src/PATENTS" libaom-PATENTS
    copy_license "$DEPS/libaom-src/third_party/fastfeat/LICENSE" libaom-fastfeat-LICENSE
    copy_license "$DEPS/libaom-src/third_party/vector/LICENSE" libaom-vector-LICENSE
    copy_license "$DEPS/libaom-src/third_party/x86inc/LICENSE" libaom-x86inc-LICENSE
    copy_license "$DEPS/libyuv-src/LICENSE" libyuv-LICENSE
    copy_license "$DEPS/libyuv-src/PATENTS" libyuv-PATENTS
fi
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

echo "==> Signing..."
if [ -n "${CODESIGN_IDENTITY:-}" ]; then
    codesign --force --deep --options runtime --timestamp \
        --entitlements "$ROOT/Resources/conv3rt.entitlements" \
        --sign "$CODESIGN_IDENTITY" "$BUNDLE"
    codesign --verify --deep --strict --verbose=2 "$BUNDLE"
    SIGN_STATE="signed with '$CODESIGN_IDENTITY' (Hardened Runtime). Run scripts/notarize.sh before distributing."
else
    codesign --force --deep --sign - "$BUNDLE" 2>/dev/null || true
    SIGN_STATE="ad-hoc signed (NOT for distribution; set CODESIGN_IDENTITY to sign properly)."
fi

echo "==> Moving to arch-named folder..."
mkdir -p "$OUTROOT"
mv "$BUNDLE" "$OUTROOT/"
CONTENTS="$OUTROOT/$APP_NAME.app"

echo "==> Zipping..."
ditto -c -k --keepParent "$CONTENTS" "$ARCHIVE"
shasum -a 256 "$ARCHIVE" | awk '{print $1}' > "$ARCHIVE.sha256"

APP_SIZE=$(du -sh "$CONTENTS" | awk '{print $1}')
ZIP_SIZE=$(du -sh "$ARCHIVE" | awk '{print $1}')
BIN_SIZE=$(du -sh "$CONTENTS/Contents/MacOS/$APP_NAME" | awk '{print $1}')

echo ""
echo "==================== conv3rt $VERSION ($ARCH) ===================="
echo "Bundle:        $CONTENTS"
echo "Zip:           $ARCHIVE  ($ZIP_SIZE)"
echo "App size:      $APP_SIZE"
echo "Executable:    $BIN_SIZE"
echo "Signing:       $SIGN_STATE"
echo "Checksum:      $ARCHIVE.sha256"
echo "=================================================================="
