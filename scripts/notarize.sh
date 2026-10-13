#!/usr/bin/env bash
# Notarizes and staples a signed conv3rt.app, then re-zips it.
#
# Prerequisites (run once, on your machine):
#   xcrun notarytool store-credentials conv3rt-profile \
#     --apple-id "you@example.com" --team-id TEAMID --password "app-specific-pw"
#
# Usage:
#   scripts/notarize.sh dist/conv3rt-<ver>-apple-silicon/conv3rt.app
set -euo pipefail

APP="${1:?usage: notarize.sh <path/to/conv3rt.app>}"
PROFILE="${NOTARY_PROFILE:-conv3rt-profile}"

echo "==> Verifying signature before notarization ..."
codesign --verify --deep --strict --verbose=2 "$APP"
spctl -a -vvv -t exec "$APP" || echo "(spctl may fail until notarized — expected)"

TMPZIP="$(mktemp -d)/conv3rt.zip"
echo "==> Zipping for notarization ..."
ditto -c -k --keepParent "$APP" "$TMPZIP"

echo "==> Submitting to the notary service (this can take a few minutes) ..."
xcrun notarytool submit "$TMPZIP" --keychain-profile "$PROFILE" --wait

echo "==> Stapling ..."
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "==> Gatekeeper assessment after stapling ..."
spctl -a -vvv -t exec "$APP"

echo "==> Re-zipping the stapled app next to it ..."
OUT="${APP%.app}.zip"
ditto -c -k --keepParent "$APP" "$OUT"
shasum -a 256 "$OUT" | awk '{print $1}' > "$OUT.sha256"
echo "Notarized package: $OUT"
