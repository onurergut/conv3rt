#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
FIXTURE="$TEMP/project with spaces"
TOOLS="$FIXTURE/.build/artifacts/sparkle/Sparkle/bin"
mkdir -p "$FIXTURE/scripts" "$FIXTURE/updates" "$TOOLS" "$TEMP/releases"

empty_feed() {
    local arch="$1" title="$2"
    cat > "$FIXTURE/updates/appcast-$arch.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>$title</title>
    <link>https://github.com/onurergut/conv3rt</link>
    <description>Stable conv3rt updates for $arch. No published updates yet.</description>
    <language>en</language>
  </channel>
</rss>
EOF
}

for arch in arm64 x86_64; do
    feed="$ROOT/updates/appcast-$arch.xml"
    /usr/bin/xmllint --noout --nonet "$feed"
    [[ "$(/usr/bin/xmllint --xpath 'count(/rss/channel)' "$feed")" == 1 ]]
    [[ "$(/usr/bin/xmllint --xpath 'count(/rss/channel/item)' "$feed")" =~ ^[0-9]+$ ]]
    [[ "$(/usr/bin/xmllint --xpath 'count(/rss/channel/enclosure)' "$feed")" =~ ^[0-9]+$ ]]
done
empty_feed arm64 'conv3rt for Apple Silicon'
empty_feed x86_64 'conv3rt for Intel'
printf 'PASS per-architecture RSS feed XML and isolated empty fixtures\n'

cp "$ROOT/scripts/generate-appcast.swift" "$FIXTURE/scripts/"
swiftc "$FIXTURE/scripts/generate-appcast.swift" -o "$TEMP/generate-appcast"

cat > "$FIXTURE/scripts/verify-release.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ $# == 5 && "$2" == "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$1/Contents/Info.plist")" ]]
[[ "$3" == arm64 || "$3" == x86_64 ]]
[[ "$4" == release && "$5" == "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$1/Contents/Info.plist")" ]]
[[ -s "$(dirname "$1")/conv3rt-$2-${FIXTURE_LABEL:?}.zip.sha256" ]]
printf 'verify\n' >> "${FIXTURE_CALLS:?}"
[[ "${FIXTURE_BAD_VERIFY:-0}" == 0 ]]
EOF

cat > "$TOOLS/sign_update" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == --account && "$2" == conv3rt-test ]]
shift 2
if [[ "$1" == --verify ]]; then
    [[ $# == 3 && "$3" == "${FIXTURE_SIGNATURE:?}" ]]
    printf 'signature-verify\n' >> "${FIXTURE_CALLS:?}"
    [[ "${FIXTURE_BAD_SIGNATURE_VERIFY:-0}" == 0 ]]
    exit
fi
[[ $# == 1 && -s "$1" ]]
printf 'sign\n' >> "${FIXTURE_CALLS:?}"
size="$(stat -f '%z' "$1")"
case "${FIXTURE_SIGN_MODE:-valid}" in
    size) size=$((size + 1)) ;;
    malformed) printf 'not a signature\n'; exit ;;
    short) printf 'sparkle:edSignature="YQ==" length="%s"\n' "$size"; exit ;;
    duplicate) printf 'sparkle:edSignature="%s" length="%s" length="%s"\n' "$FIXTURE_SIGNATURE" "$size" "$size"; exit ;;
    extra) printf 'sparkle:edSignature="%s" length="%s" other="bad"\n' "$FIXTURE_SIGNATURE" "$size"; exit ;;
    tamper) printf 'changed ZIP bytes\n' >> "$1" ;;
    same-size-tamper) /bin/dd if=/dev/zero of="$1" bs=1 count=1 conv=notrunc 2>/dev/null ;;
    source-tamper) printf 'changed original\n' >> "${FIXTURE_SOURCE:?}" ;;
esac
printf 'sparkle:edSignature="%s" length="%s"\n' "$FIXTURE_SIGNATURE" "$size"
EOF
cat > "$TOOLS/generate_keys" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ $# == 3 && "$1" == --account && "$2" == conv3rt-test && "$3" == -p ]]
printf '%s\n' "${FIXTURE_PUBLIC_KEY:-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=}"
EOF
chmod +x "$FIXTURE/scripts/verify-release.sh" "$TOOLS/sign_update" "$TOOLS/generate_keys"
export FIXTURE_SIGNATURE=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==
export FIXTURE_CALLS="$TEMP/calls"

make_release() {
    local arch="$1" version="$2" build="$3" minimum="${4:-14.0}"
    FIXTURE_LABEL=apple-silicon
    [[ "$arch" != x86_64 ]] || FIXTURE_LABEL=intel
    export FIXTURE_LABEL
    local folder="$TEMP/releases/$version-$build-$FIXTURE_LABEL"
    mkdir -p "$folder/conv3rt.app/Contents/MacOS"
    local plist="$folder/conv3rt.app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Clear dict' "$plist" >/dev/null
    /usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string com.conv3rt.app' "$plist"
    /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $version" "$plist"
    /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $build" "$plist"
    /usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string $minimum" "$plist"
    /usr/libexec/PlistBuddy -c "Add :SUFeedURL string https://raw.githubusercontent.com/onurergut/conv3rt/main/updates/appcast-$arch.xml" "$plist"
    /usr/libexec/PlistBuddy -c 'Add :SUPublicEDKey string AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=' "$plist"
    printf 'fixture executable\n' > "$folder/conv3rt.app/Contents/MacOS/conv3rt"
    ARCHIVE="$folder/conv3rt-$version-$FIXTURE_LABEL.zip"
    /usr/bin/ditto -c -k --keepParent "$folder/conv3rt.app" "$ARCHIVE"
    ASSET="https://github.com/onurergut/conv3rt/releases/download/v$version/$(basename "$ARCHIVE")"
    export FIXTURE_SOURCE="$ARCHIVE"
}

generate() {
    "$TEMP/generate-appcast" --archive "$ARCHIVE" --asset-url "$ASSET" --arch "${ARCH:-arm64}" --account conv3rt-test "$@" > "$TEMP/generate.log" 2>&1
}

expect_failure() {
    local reason="$1"; shift
    local before after
    before="$(shasum -a 256 "$FIXTURE/updates/"*.xml)"
    if generate "$@"; then
        printf 'FAIL accepted %s\n' "$reason" >&2
        exit 1
    fi
    after="$(shasum -a 256 "$FIXTURE/updates/"*.xml)"
    [[ "$before" == "$after" ]] || { printf 'FAIL feed changed after %s\n' "$reason" >&2; exit 1; }
    printf 'PASS rejects %s without changing feeds\n' "$reason"
}

make_release arm64 0.6.0 600
for bad_url in \
    "http://github.com/onurergut/conv3rt/releases/download/v0.6.0/$(basename "$ARCHIVE")" \
    "https://user@github.com/onurergut/conv3rt/releases/download/v0.6.0/$(basename "$ARCHIVE")" \
    "https://github.com:443/onurergut/conv3rt/releases/download/v0.6.0/$(basename "$ARCHIVE")" \
    "https://github.com.evil.example/onurergut/conv3rt/releases/download/v0.6.0/$(basename "$ARCHIVE")" \
    "https://github.com/someone/conv3rt/releases/download/v0.6.0/$(basename "$ARCHIVE")" \
    "https://github.com/onurergut/conv3rt/releases/download/v0.6.0/$(basename "$ARCHIVE")?token=bad" \
    "https://github.com/onurergut/conv3rt/releases/download/v0.6.0/$(basename "$ARCHIVE")#fragment" \
    'https://github.com/onurergut/conv3rt/releases/download/v0.6.0/../conv3rt-0.6.0-apple-silicon.zip' \
    'https://github.com/onurergut/conv3rt/releases/download/v0.5.0/conv3rt-0.6.0-apple-silicon.zip' \
    'https://github.com/onurergut/conv3rt/releases/download/v0.6.0/conv3rt-0.6.0-intel.zip' \
    'file:///tmp/archive.zip'; do
    expect_failure "asset URL $bad_url" --asset-url "$bad_url"
done
expect_failure 'unsupported architecture' --arch universal
expect_failure 'wrong architecture feed' --arch x86_64
export FIXTURE_BAD_VERIFY=1
expect_failure 'release verification failure'
unset FIXTURE_BAD_VERIFY
export FIXTURE_BAD_SIGNATURE_VERIFY=1
expect_failure 'official signature verification failure'
unset FIXTURE_BAD_SIGNATURE_VERIFY
export FIXTURE_PUBLIC_KEY=BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=
expect_failure 'signing account public key mismatch'
unset FIXTURE_PUBLIC_KEY
for mode in size malformed short duplicate extra tamper same-size-tamper source-tamper; do
    export FIXTURE_SIGN_MODE="$mode"
    make_release arm64 0.6.0 600
    expect_failure "signing output or archive mutation: $mode"
done
unset FIXTURE_SIGN_MODE
for bad_version in bad 0.6 0.6.0-beta; do
    make_release arm64 "$bad_version" 600
    expect_failure "non-stable version $bad_version"
done
for bad_build in bad 0 1.2 -1; do
    make_release arm64 0.6.0 "$bad_build"
    expect_failure "invalid build $bad_build"
done
make_release arm64 0.6.0 600 bad
expect_failure 'invalid minimum macOS version'

make_release arm64 0.6.0 600
rm -f "$FIXTURE_CALLS"
generate --title 'conv3rt <stable> & "signed"' || { /bin/cat "$TEMP/generate.log"; exit 1; }
FEED="$FIXTURE/updates/appcast-arm64.xml"
/usr/bin/xmllint --noout --nonet "$FEED"
[[ "$(/usr/bin/xmllint --xpath 'string(/rss/channel/item/title)' "$FEED")" == 'conv3rt <stable> & "signed"' ]]
[[ "$(/usr/bin/xmllint --xpath 'string(/rss/channel/item/enclosure/@length)' "$FEED")" == "$(stat -f '%z' "$ARCHIVE")" ]]
[[ "$(/usr/bin/xmllint --xpath 'string(/rss/channel/item/*[local-name()="version"])' "$FEED")" == 600 ]]
[[ "$(/usr/bin/xmllint --xpath 'string(/rss/channel/item/*[local-name()="minimumSystemVersion"])' "$FEED")" == 14.0 ]]
[[ "$(< "$FIXTURE_CALLS")" == $'verify\nsign\nsignature-verify' ]]
printf 'PASS structured XML escaping, plist metadata, exact length, verifier-before-signing\n'
expect_failure 'duplicate build'
make_release arm64 0.6.1 599
expect_failure 'build downgrade'
make_release arm64 0.5.9 601
expect_failure 'version downgrade with newer build'
make_release arm64 0.6.1 601
generate || { /bin/cat "$TEMP/generate.log"; exit 1; }
[[ "$(/usr/bin/xmllint --xpath 'string(/rss/channel/item[1]/*[local-name()="version"])' "$FEED")" == 601 ]]
[[ "$(/usr/bin/xmllint --xpath 'count(/rss/channel/item)' "$FEED")" == 2 ]]
printf 'PASS newest-first monotonic feed with preserved history\n'

make_release x86_64 0.6.0 600
ARCH=x86_64 generate || { /bin/cat "$TEMP/generate.log"; exit 1; }
[[ "$(/usr/bin/xmllint --xpath 'count(/rss/channel/item)' "$FIXTURE/updates/appcast-x86_64.xml")" == 1 ]]
[[ "$(/usr/bin/xmllint --xpath 'count(/rss/channel/item)' "$FEED")" == 2 ]]
printf 'PASS independent Intel feed\n'
printf 'All appcast fixture tests passed; no production signing key or network used.\n'
