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
OUTROOT="$DIST/conv3rt-$VERSION-$([ "$ARCH" = "arm64" ] && echo apple-silicon || echo intel)"

echo "==> Building $APP_NAME for $ARCH (release)..."
cd "$ROOT"
swift build -c release --arch "$ARCH"
BIN="$(swift build -c release --arch "$ARCH" --show-bin-path)/$APP_NAME"
[ -x "$BIN" ] || { echo "build did not produce $BIN"; exit 1; }

echo "==> Assembling $BUNDLE..."
rm -rf "$BUNDLE" "$OUTROOT"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN" "$BUNDLE/Contents/MacOS/$APP_NAME"
sed "s/0\.1\.0/$VERSION/g" "$ROOT/Resources/Info.plist" > "$BUNDLE/Contents/Info.plist"
cp "$ROOT/THIRD_PARTY_NOTICES.txt" "$BUNDLE/Contents/Resources/" 2>/dev/null || true
cp "$ROOT/Resources/conv3rt.icns" "$BUNDLE/Contents/Resources/conv3rt.icns" 2>/dev/null || true
# Bundled third-party license texts (required for redistribution).
mkdir -p "$BUNDLE/Contents/Resources/licenses"
cp "$ROOT/ThirdParty/libwebp-c/COPYING" "$BUNDLE/Contents/Resources/licenses/libwebp-COPYING.txt" 2>/dev/null || true
cp "$ROOT/ThirdParty/libwebp-c/PATENTS" "$BUNDLE/Contents/Resources/licenses/libwebp-PATENTS.txt" 2>/dev/null || true
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
( cd "$OUTROOT" && ditto -c -k --keepParent "$APP_NAME.app" "conv3rt-$VERSION-$ARCH.zip" )
shasum -a 256 "$OUTROOT/conv3rt-$VERSION-$ARCH.zip" | awk '{print $1}' > "$OUTROOT/conv3rt-$VERSION-$ARCH.zip.sha256"

APP_SIZE=$(du -sh "$CONTENTS" | awk '{print $1}')
ZIP_SIZE=$(du -sh "$OUTROOT/conv3rt-$VERSION-$ARCH.zip" | awk '{print $1}')
BIN_SIZE=$(du -sh "$CONTENTS/Contents/MacOS/$APP_NAME" | awk '{print $1}')

echo ""
echo "==================== conv3rt $VERSION ($ARCH) ===================="
echo "Bundle:        $CONTENTS"
echo "Zip:           $OUTROOT/conv3rt-$VERSION-$ARCH.zip  ($ZIP_SIZE)"
echo "App size:      $APP_SIZE"
echo "Executable:    $BIN_SIZE"
echo "Signing:       $SIGN_STATE"
echo "Checksum:      $OUTROOT/conv3rt-$VERSION-$ARCH.zip.sha256"
echo "=================================================================="
