#!/usr/bin/env bash
# Packages an already-built (and, if desired, already-signed) conv3rt.app into a
# compressed .dmg for drag-to-install distribution.
#
# This script does NOT build, sign, or notarize anything — run
# scripts/package.sh first so the signed bundle exists, then notarize the .dmg
# with your own tooling if you need a distributable artifact.
#
# The bundle is expected at, matching scripts/package.sh's layout:
#   dist/conv3rt-<version>-<apple-silicon|intel>/conv3rt.app
#
# Usage: scripts/make-dmg.sh [arm64|x86_64] [version]
set -euo pipefail

ARCH="${1:-$(uname -m)}"
VERSION="${2:-0.1.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP_NAME="conv3rt"

# Same folder-naming rule package.sh uses.
ARCH_LABEL="$([ "$ARCH" = "arm64" ] && echo apple-silicon || echo intel)"
OUTROOT="$DIST/conv3rt-$VERSION-$ARCH_LABEL"
CONTENTS="$OUTROOT/$APP_NAME.app"
DMG="$OUTROOT/conv3rt-$VERSION-$ARCH.dmg"

if [ ! -d "$CONTENTS" ]; then
    echo "error: no app bundle at:" >&2
    echo "         $CONTENTS" >&2
    echo "       Build and sign it first: scripts/package.sh $ARCH $VERSION" >&2
    exit 1
fi

echo "==> Staging $CONTENTS..."
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/conv3rt-dmg.XXXXXX")"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

# Copy the bundle, then add the /Applications symlink so the mounted volume
# supports drag-install. ditto preserves the code signature and resources.
ditto "$CONTENTS" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"

echo "==> Building compressed DMG..."
rm -f "$DMG"
hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$STAGE" \
    -ov \
    -format UDZO \
    "$DMG" >/dev/null

[ -f "$DMG" ] || { echo "error: hdiutil did not produce $DMG" >&2; exit 1; }

SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"
echo "$SHA" > "$DMG.sha256"
DMG_SIZE="$(du -sh "$DMG" | awk '{print $1}')"

echo ""
echo "==================== conv3rt $VERSION ($ARCH) DMG ===================="
echo "App bundle:    $CONTENTS"
echo "DMG:           $DMG  ($DMG_SIZE)"
echo "SHA-256:       $SHA"
echo "Checksum file: $DMG.sha256"
echo "Note:          the DMG is unsigned and not notarized."
echo "===================================================================="
