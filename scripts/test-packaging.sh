#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
FIXTURE="$TEMP/project with spaces"
TOOLS="$TEMP/tools"
mkdir -p "$FIXTURE/scripts" "$FIXTURE/Resources" "$FIXTURE/ThirdParty/libwebp-c" "$TOOLS"
cp "$ROOT/scripts/"*.sh "$FIXTURE/scripts/"
cp "$ROOT/Resources/Info.plist" "$ROOT/Resources/conv3rt.entitlements" "$ROOT/Resources/conv3rt.icns" "$FIXTURE/Resources/"
cp "$ROOT/THIRD_PARTY_NOTICES.txt" "$FIXTURE/"
cp "$ROOT/ThirdParty/libwebp-c/COPYING" "$ROOT/ThirdParty/libwebp-c/PATENTS" "$FIXTURE/ThirdParty/libwebp-c/"

cat > "$TOOLS/swift" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ " $* " == *" --show-bin-path "* ]]; then
    printf '%s\n' "$PWD/fake-build"
else
    mkdir -p "$PWD/fake-build"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$PWD/fake-build/conv3rt"
    chmod +x "$PWD/fake-build/conv3rt"
fi
EOF
for tool in codesign spctl xcrun nm; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$TOOLS/$tool"
done
chmod +x "$TOOLS/"*
export PATH="$TOOLS:$PATH"
export CODESIGN_IDENTITY="Fixture identity"

assert_file() {
    [[ -s "$1" ]] || { printf 'Missing or empty: %s\n' "$1" >&2; exit 1; }
}

for architecture in arm64 x86_64; do
    label=apple-silicon
    [[ "$architecture" != x86_64 ]] || label=intel
    folder="$FIXTURE/dist/conv3rt-9.8.7-$label"
    archive="$folder/conv3rt-9.8.7-$label.zip"
    bash "$FIXTURE/scripts/package.sh" "$architecture" 9.8.7 > "$TEMP/package.log" 2>&1
    assert_file "$archive"
    assert_file "$archive.sha256"
    expected="$(shasum -a 256 "$archive")"
    [[ "$(< "$archive.sha256")" == "${expected%% *}" ]]
    bash "$FIXTURE/scripts/notarize.sh" "$folder/conv3rt.app" > "$TEMP/notarize.log" 2>&1
    assert_file "$archive"
    expected="$(shasum -a 256 "$archive")"
    [[ "$(< "$archive.sha256")" == "${expected%% *}" ]]
    [[ ! -e "$folder/conv3rt.zip" ]]
    printf 'PASS package naming and checksum: %s\n' "$architecture"
done

mv "$FIXTURE/ThirdParty/libwebp-c/COPYING" "$TEMP/webp-COPYING"
if bash "$FIXTURE/scripts/package.sh" arm64 9.8.7 > "$TEMP/missing-license.log" 2>&1; then
    printf 'Packaging accepted a missing WebP license.\n' >&2
    exit 1
fi
mv "$TEMP/webp-COPYING" "$FIXTURE/ThirdParty/libwebp-c/COPYING"
printf 'PASS missing WebP license blocks packaging\n'

cat > "$TOOLS/nm" <<'EOF'
#!/usr/bin/env bash
if [[ "${FIXTURE_CODECS:-}" == all ]]; then
    printf '0001 T _conv3rt_jxl_encode_rgba\n0002 T _conv3rt_avif_encode_rgba\n'
fi
EOF
chmod +x "$TOOLS/nm"
export FIXTURE_CODECS=all
if bash "$FIXTURE/scripts/package.sh" arm64 9.8.7 > "$TEMP/missing-license.log" 2>&1; then
    printf 'Packaging accepted missing optional-codec licenses.\n' >&2
    exit 1
fi

licenses=(
    ThirdParty/jxl-src/LICENSE ThirdParty/jxl-src/PATENTS
    ThirdParty/jxl-src/third_party/highway/LICENSE
    ThirdParty/jxl-src/third_party/brotli/LICENSE
    ThirdParty/jxl-src/third_party/lcms/LICENSE
    ThirdParty/jxl-src/third_party/libpng/LICENSE
    ThirdParty/jxl-src/third_party/zlib/LICENSE
    ThirdParty/avif-src/LICENSE
    ThirdParty/avif-build-arm64/_deps/libaom-src/LICENSE
    ThirdParty/avif-build-arm64/_deps/libaom-src/PATENTS
    ThirdParty/avif-build-arm64/_deps/libaom-src/third_party/fastfeat/LICENSE
    ThirdParty/avif-build-arm64/_deps/libaom-src/third_party/vector/LICENSE
    ThirdParty/avif-build-arm64/_deps/libaom-src/third_party/x86inc/LICENSE
    ThirdParty/avif-build-arm64/_deps/libyuv-src/LICENSE
    ThirdParty/avif-build-arm64/_deps/libyuv-src/PATENTS
)
for license in "${licenses[@]}"; do
    mkdir -p "$(dirname "$FIXTURE/$license")"
    printf 'Fixture license: %s\n' "$license" > "$FIXTURE/$license"
done
bash "$FIXTURE/scripts/package.sh" arm64 9.8.7 > "$TEMP/package.log" 2>&1
folder="$FIXTURE/dist/conv3rt-9.8.7-apple-silicon"
for name in libwebp-COPYING libwebp-PATENTS libjxl-LICENSE libjxl-PATENTS highway-LICENSE \
    brotli-LICENSE lcms2-LICENSE libpng-LICENSE zlib-LICENSE libavif-LICENSE \
    libaom-LICENSE libaom-PATENTS libaom-fastfeat-LICENSE libaom-vector-LICENSE \
    libaom-x86inc-LICENSE libyuv-LICENSE libyuv-PATENTS; do
    assert_file "$folder/conv3rt.app/Contents/Resources/licenses/$name.txt"
done
for license in "${licenses[@]}"; do
    mv "$FIXTURE/$license" "$TEMP/removed-license"
    if bash "$FIXTURE/scripts/package.sh" arm64 9.8.7 > "$TEMP/missing-license.log" 2>&1; then
        printf 'Packaging accepted missing license: %s\n' "$license" >&2
        exit 1
    fi
    mv "$TEMP/removed-license" "$FIXTURE/$license"
done
printf 'PASS optional-codec licenses and every missing-license failure\n'

cat > "$TOOLS/lipo" <<'EOF'
#!/usr/bin/env bash
printf 'arm64\n'
EOF
chmod +x "$TOOLS/lipo"
bash "$FIXTURE/scripts/package.sh" arm64 9.8.7 > "$TEMP/package.log" 2>&1
app="$folder/conv3rt.app"
archive="$folder/conv3rt-9.8.7-apple-silicon.zip"
run_verifier() {
    bash "$FIXTURE/scripts/verify-release.sh" "$app" 9.8.7 arm64 --development > "$TEMP/verify.log" 2>&1
}
run_verifier || { /bin/cat "$TEMP/verify.log"; exit 1; }

for change in version architecture checksum license executable signature staple gatekeeper archive; do
    cp "$app/Contents/Info.plist" "$TEMP/Info.plist"
    case "$change" in
        version) /usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 0.0.0' "$app/Contents/Info.plist" ;;
        architecture) printf '#!/usr/bin/env bash\nprintf "x86_64\\n"\n' > "$TOOLS/lipo" ;;
        checksum) cp "$archive.sha256" "$TEMP/checksum"; printf 'bad-checksum\n' > "$archive.sha256" ;;
        license) mv "$app/Contents/Resources/licenses/libaom-LICENSE.txt" "$TEMP/libaom-LICENSE.txt" ;;
        executable) printf '#!/usr/bin/env bash\nexit 1\n' > "$app/Contents/MacOS/conv3rt" ;;
        signature) printf '#!/usr/bin/env bash\nexit 1\n' > "$TOOLS/codesign" ;;
        staple) printf '#!/usr/bin/env bash\nexit 1\n' > "$TOOLS/xcrun" ;;
        gatekeeper) printf '#!/usr/bin/env bash\nexit 1\n' > "$TOOLS/spctl" ;;
        archive)
            cp "$archive" "$TEMP/archive.zip"
            cp "$archive.sha256" "$TEMP/checksum"
            /usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 0.0.0' "$app/Contents/Info.plist"
            ditto -c -k --keepParent "$app" "$archive"
            shasum -a 256 "$archive" | /usr/bin/awk '{print $1}' > "$archive.sha256"
            cp "$TEMP/Info.plist" "$app/Contents/Info.plist"
            ;;
    esac
    if [[ "$change" == staple || "$change" == gatekeeper ]]; then
        if bash "$FIXTURE/scripts/verify-release.sh" "$app" 9.8.7 arm64 > "$TEMP/verify.log" 2>&1; then
            printf 'Release verifier accepted broken %s.\n' "$change" >&2; exit 1
        fi
    elif run_verifier; then
        printf 'Release verifier accepted broken %s.\n' "$change" >&2; exit 1
    fi
    cp "$TEMP/Info.plist" "$app/Contents/Info.plist"
    printf '#!/usr/bin/env bash\nprintf "arm64\\n"\n' > "$TOOLS/lipo"
    [[ "$change" != checksum ]] || cp "$TEMP/checksum" "$archive.sha256"
    [[ "$change" != archive ]] || { cp "$TEMP/archive.zip" "$archive"; cp "$TEMP/checksum" "$archive.sha256"; }
    [[ "$change" != license ]] || mv "$TEMP/libaom-LICENSE.txt" "$app/Contents/Resources/licenses/libaom-LICENSE.txt"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$app/Contents/MacOS/conv3rt"
    for tool in codesign spctl xcrun; do
        printf '#!/usr/bin/env bash\nexit 0\n' > "$TOOLS/$tool"
    done
    printf 'PASS release verifier rejects broken %s\n' "$change"
done
run_verifier
printf 'PASS development verifier after fixture restoration\n'
