#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ORIGINAL_PATH="$PATH"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
FIXTURE="$TEMP/project with spaces"
TOOLS="$TEMP/tools"
mkdir -p "$FIXTURE/scripts" "$FIXTURE/Resources" "$FIXTURE/ThirdParty/libwebp-c" "$TOOLS"
cp "$ROOT/scripts/"*.sh "$FIXTURE/scripts/"
cp "$ROOT/Resources/Info.plist" "$ROOT/Resources/conv3rt.entitlements" "$ROOT/Resources/conv3rt.icns" "$FIXTURE/Resources/"
cp "$ROOT/THIRD_PARTY_NOTICES.txt" "$FIXTURE/"
cp "$ROOT/ThirdParty/libwebp-c/COPYING" "$ROOT/ThirdParty/libwebp-c/PATENTS" "$FIXTURE/ThirdParty/libwebp-c/"
# Fresh-clone fixtures never read production update keys or codec build trees.
printf 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\n' > "$FIXTURE/Resources/update-public-key.txt"
SPARKLE="$FIXTURE/.build/artifacts/sparkle/Sparkle"
FRAMEWORK="$SPARKLE/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
FRAMEWORK_VERSION="$FRAMEWORK/Versions/B"
mkdir -p "$FRAMEWORK_VERSION/Resources"
printf 'Fixture Sparkle license\n' > "$SPARKLE/LICENSE"
cp "$ROOT/Resources/Info.plist" "$FRAMEWORK_VERSION/Resources/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 2.10.0' "$FRAMEWORK_VERSION/Resources/Info.plist"
for name in Sparkle Autoupdate; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$FRAMEWORK_VERSION/$name"
    chmod +x "$FRAMEWORK_VERSION/$name"
done
for helper in Updater.app XPCServices/Downloader.xpc XPCServices/Installer.xpc; do
    name="$(basename "${helper%.*}")"
    mkdir -p "$FRAMEWORK_VERSION/$helper/Contents/MacOS"
    cp "$ROOT/Resources/Info.plist" "$FRAMEWORK_VERSION/$helper/Contents/Info.plist"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$FRAMEWORK_VERSION/$helper/Contents/MacOS/$name"
    chmod +x "$FRAMEWORK_VERSION/$helper/Contents/MacOS/$name"
done
ln -s B "$FRAMEWORK/Versions/Current"
for name in Sparkle Autoupdate Resources Updater.app XPCServices; do
    ln -s "Versions/Current/$name" "$FRAMEWORK/$name"
done

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
cat > "$TOOLS/codesign" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
object="${!#}"
if [[ " $* " == *" --force "* ]]; then
    [[ " $* " != *" --deep "* ]] || exit 1
    if [[ " $* " != *" --sign - "* ]]; then
        [[ " $* " == *" --options runtime "* && " $* " == *" --timestamp "* ]] || exit 1
    fi
    if [[ "$object" != */conv3rt.app ]]; then
        [[ " $* " != *" --entitlements "* ]] || exit 1
    fi
    printf '%s\n' "$object" >> "$FIXTURE_SIGN_LOG"
    [[ -z "${FIXTURE_SIGN_FAILURE:-}" || "$object" != *"$FIXTURE_SIGN_FAILURE" ]] || exit 1
else
    [[ "${FIXTURE_BAD_SIGNATURE:-0}" == 0 ]] || exit 1
fi
EOF
cat > "$TOOLS/nm" <<'EOF'
#!/usr/bin/env bash
if [[ "${FIXTURE_CODECS:-}" == all ]]; then
    printf '0001 T _conv3rt_jxl_encode_rgba\n0002 T _conv3rt_avif_encode_rgba\n'
fi
EOF
cat > "$TOOLS/lipo" <<'EOF'
#!/usr/bin/env bash
if [[ "${!#}" == *Sparkle.framework/* ]]; then
    printf 'x86_64 arm64\n'
else
    printf '%s\n' "${FIXTURE_ARCH:-arm64}"
fi
EOF
cat > "$TOOLS/otool" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
binary="${!#}"
if [[ "$1" == -L ]]; then
    printf '%s:\n' "$binary"
    if [[ "$binary" == */MacOS/conv3rt && "${FIXTURE_DEPENDENCY:-}" != no-sparkle ]]; then
        printf '\t@rpath/Sparkle.framework/Versions/B/Sparkle (compatibility version 1.6.0, current version 2.10.0)\n'
    fi
    if [[ "${FIXTURE_DEPENDENCY:-}" == no-libraries ]]; then exit 0; fi
    printf '\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1.0.0)\n'
    case "${FIXTURE_DEPENDENCY:-}" in
        homebrew) printf '\t/opt/homebrew/lib/libbad.dylib (compatibility version 1.0.0)\n' ;;
        missing) printf '\t@rpath/missing.dylib (compatibility version 1.0.0)\n' ;;
        escape) printf '\t@loader_path/../../../../outside.dylib (compatibility version 1.0.0)\n' ;;
        helper) [[ "$binary" != */Autoupdate ]] || printf '\t/Users/developer/libbad.dylib (compatibility version 1.0.0)\n' ;;
        helper-rpath) [[ "$binary" != */Autoupdate ]] || printf '\t@rpath/Sparkle.framework/Versions/B/Sparkle (compatibility version 1.0.0)\n' ;;
    esac
else
    if [[ "$binary" == */MacOS/conv3rt ]]; then
        printf 'Load command 1\n          cmd LC_RPATH\n      cmdsize 48\n         path @executable_path/../Frameworks (offset 12)\n'
        printf 'Load command 4\n          cmd LC_RPATH\n      cmdsize 80\n         path /usr/lib/swift (offset 12)\n'
        if [[ "$(< "$binary")" != *'# fixture rpath removed'* ]]; then
            printf 'Load command 2\n          cmd LC_RPATH\n      cmdsize 128\n         path %s/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64 (offset 12)\n' "$FIXTURE_ROOT"
        fi
        if [[ "$(< "$binary")" != *'# developer rpath removed'* ]]; then
            printf 'Load command 3\n          cmd LC_RPATH\n      cmdsize 160\n         path /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift-6.2/macosx (offset 12)\n'
        fi
    fi
    if [[ "${FIXTURE_BAD_RPATH:-0}" == 1 ]]; then
        printf 'Load command 3\n          cmd LC_RPATH\n      cmdsize 48\n         path /opt/homebrew/lib (offset 12)\n'
    fi
fi
EOF
cat > "$TOOLS/install_name_tool" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$2" in
    "$FIXTURE_ROOT"/.build/*|/Applications/*/Contents/Developer/*|/Library/Developer/*) ;;
    *) exit 1 ;;
esac
if [[ "$2" == /Applications/*/Contents/Developer/* || "$2" == /Library/Developer/* ]]; then
    printf '\n# developer rpath removed\n' >> "$3"
else
    printf '\n# fixture rpath removed\n' >> "$3"
fi
EOF
for tool in spctl xcrun; do
    printf '#!/usr/bin/env bash\nexit "${FIXTURE_ASSESSMENT_FAILURE:-0}"\n' > "$TOOLS/$tool"
done
chmod +x "$TOOLS/"*
export PATH="$TOOLS:$PATH"
export CODESIGN_IDENTITY="Fixture identity"
export FIXTURE_ROOT="$FIXTURE"
export FIXTURE_SIGN_LOG="$TEMP/signing.log"

fail() { printf '%s\n' "$*" >&2; exit 1; }
assert_file() { [[ -s "$1" ]] || fail "Missing or empty: $1"; }
expect_package_failure() {
    if bash "$FIXTURE/scripts/package.sh" arm64 9.8.7 42 > "$TEMP/package.log" 2>&1; then
        fail "Packaging accepted $1."
    fi
    printf 'PASS packaging rejects %s\n' "$1"
}
package() {
    : > "$FIXTURE_SIGN_LOG"
    bash "$FIXTURE/scripts/package.sh" "${1:-arm64}" "${2:-9.8.7}" "${3:-42}" > "$TEMP/package.log" 2>&1 || { /bin/cat "$TEMP/package.log"; exit 1; }
}

# Regression tests fail against pre-Sparkle packaging before happy-path checks.
mv "$FRAMEWORK" "$TEMP/Sparkle.framework"
expect_package_failure 'missing Sparkle framework'
mv "$TEMP/Sparkle.framework" "$FRAMEWORK"
mv "$FIXTURE/Resources/update-public-key.txt" "$TEMP/public-key"
expect_package_failure 'missing update public key'
mv "$TEMP/public-key" "$FIXTURE/Resources/update-public-key.txt"
printf 'invalid-key\n' > "$FIXTURE/Resources/update-public-key.txt"
expect_package_failure 'invalid update public key'
printf 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\n' > "$FIXTURE/Resources/update-public-key.txt"
for helper in Autoupdate Updater.app/Contents/MacOS/Updater XPCServices/Downloader.xpc/Contents/MacOS/Downloader XPCServices/Installer.xpc/Contents/MacOS/Installer; do
    mv "$FRAMEWORK_VERSION/$helper" "$TEMP/helper"
    expect_package_failure "missing Sparkle $helper"
    mv "$TEMP/helper" "$FRAMEWORK_VERSION/$helper"
done
mv "$SPARKLE/LICENSE" "$TEMP/Sparkle-LICENSE"
expect_package_failure 'missing Sparkle license'
mv "$TEMP/Sparkle-LICENSE" "$SPARKLE/LICENSE"
for failure in Autoupdate Downloader.xpc Installer.xpc Updater.app Sparkle.framework conv3rt.app; do
    export FIXTURE_SIGN_FAILURE="$failure"
    expect_package_failure "signing failure in $failure"
done
unset FIXTURE_SIGN_FAILURE
for dependency in homebrew missing no-sparkle no-libraries helper helper-rpath escape; do
    export FIXTURE_DEPENDENCY="$dependency"
    expect_package_failure "unsafe or missing library ($dependency)"
done
unset FIXTURE_DEPENDENCY
export FIXTURE_BAD_RPATH=1
expect_package_failure 'external runtime search path'
unset FIXTURE_BAD_RPATH

for architecture in arm64 x86_64; do
    export FIXTURE_ARCH="$architecture"
    label=apple-silicon
    [[ "$architecture" != x86_64 ]] || label=intel
    folder="$FIXTURE/dist/conv3rt-9.8.7-$label"
    archive="$folder/conv3rt-9.8.7-$label.zip"
    package "$architecture"
    assert_file "$archive"
    assert_file "$archive.sha256"
    expected="$(shasum -a 256 "$archive")"
    [[ "$(< "$archive.sha256")" == "${expected%% *}" ]]
    app="$folder/conv3rt.app"
    plist="$app/Contents/Info.plist"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")" == 42 ]]
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$plist")" == "$(< "$FIXTURE/Resources/update-public-key.txt")" ]]
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$plist")" == "https://raw.githubusercontent.com/onurergut/conv3rt/main/updates/appcast-$architecture.xml" ]]
    for flag in SUAllowsAutomaticUpdates SUAutomaticallyUpdate SUEnableSystemProfiling SUSendProfileInfo; do
        [[ "$(plutil -type "$flag" "$plist")" == bool ]]
        [[ "$(/usr/libexec/PlistBuddy -c "Print :$flag" "$plist")" == false ]]
    done
    if /usr/libexec/PlistBuddy -c 'Print :SUEnableAutomaticChecks' "$plist" > /dev/null 2>&1; then fail 'Consent flag must be absent.'; fi
    [[ -L "$app/Contents/Frameworks/Sparkle.framework/Sparkle" ]]
    [[ -x "$app/Contents/Frameworks/Sparkle.framework/Autoupdate" ]]
    assert_file "$app/Contents/Resources/licenses/Sparkle-LICENSE.txt"
    expected_order=(Autoupdate Downloader.xpc Installer.xpc Updater.app Sparkle.framework conv3rt.app)
    index=0
    while IFS= read -r signed; do
        [[ "$signed" == *"/${expected_order[$index]}" ]] || fail "Wrong signing order: $signed"
        index=$((index + 1))
    done < "$FIXTURE_SIGN_LOG"
    [[ "$index" == 6 ]] || fail 'Missing nested signing calls.'
    bash "$FIXTURE/scripts/verify-release.sh" "$app" 9.8.7 "$architecture" --development 42 > "$TEMP/verify.log" 2>&1 || { /bin/cat "$TEMP/verify.log"; exit 1; }
    # All Apple service commands are fixture tools; ditto creates real ZIPs.
    bash "$FIXTURE/scripts/notarize.sh" "$app" > "$TEMP/notarize.log" 2>&1
    expected="$(shasum -a 256 "$archive")"
    [[ "$(< "$archive.sha256")" == "${expected%% *}" ]]
    [[ ! -e "$folder/conv3rt.zip" ]]
    printf 'PASS package metadata, nested signing, archive, checksum: %s\n' "$architecture"
done
export FIXTURE_ARCH=arm64
: > "$FIXTURE_SIGN_LOG"
bash "$FIXTURE/scripts/package.sh" arm64 > "$TEMP/package.log" 2>&1
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$FIXTURE/dist/conv3rt-0.6.0-apple-silicon/conv3rt.app/Contents/Info.plist")" == 0.6.0 ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$FIXTURE/dist/conv3rt-0.6.0-apple-silicon/conv3rt.app/Contents/Info.plist")" == 2 ]]
unset CODESIGN_IDENTITY
package
export FIXTURE_SIGN_FAILURE=Autoupdate
expect_package_failure 'ad-hoc nested signing failure'
unset FIXTURE_SIGN_FAILURE
export CODESIGN_IDENTITY="Fixture identity"
printf 'PASS default version/build and strict ad-hoc signing\n'

mv "$FIXTURE/ThirdParty/libwebp-c/COPYING" "$TEMP/webp-COPYING"
expect_package_failure 'missing WebP license'
mv "$TEMP/webp-COPYING" "$FIXTURE/ThirdParty/libwebp-c/COPYING"
export FIXTURE_CODECS=all
expect_package_failure 'missing optional-codec licenses'
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
package
folder="$FIXTURE/dist/conv3rt-9.8.7-apple-silicon"
for name in libwebp-COPYING libwebp-PATENTS Sparkle-LICENSE libjxl-LICENSE libjxl-PATENTS highway-LICENSE \
    brotli-LICENSE lcms2-LICENSE libpng-LICENSE zlib-LICENSE libavif-LICENSE \
    libaom-LICENSE libaom-PATENTS libaom-fastfeat-LICENSE libaom-vector-LICENSE \
    libaom-x86inc-LICENSE libyuv-LICENSE libyuv-PATENTS; do
    assert_file "$folder/conv3rt.app/Contents/Resources/licenses/$name.txt"
done
for license in "${licenses[@]}"; do
    mv "$FIXTURE/$license" "$TEMP/removed-license"
    expect_package_failure "missing $license"
    mv "$TEMP/removed-license" "$FIXTURE/$license"
done
printf 'PASS optional-codec licenses and every missing-license failure\n'

package
app="$folder/conv3rt.app"
archive="$folder/conv3rt-9.8.7-apple-silicon.zip"
run_verifier() {
    bash "$FIXTURE/scripts/verify-release.sh" "$app" 9.8.7 arm64 --development 42 > "$TEMP/verify.log" 2>&1
}
run_verifier || { /bin/cat "$TEMP/verify.log"; exit 1; }
cp "$archive" "$TEMP/good.zip"
cp "$archive.sha256" "$TEMP/good.sha256"
restore_package() {
    rm -rf "$app"
    ditto -x -k "$TEMP/good.zip" "$folder"
    cp "$TEMP/good.zip" "$archive"
    cp "$TEMP/good.sha256" "$archive.sha256"
    unset FIXTURE_DEPENDENCY FIXTURE_BAD_RPATH FIXTURE_BAD_SIGNATURE FIXTURE_ASSESSMENT_FAILURE
    export FIXTURE_ARCH=arm64
}
rearchive() {
    ditto -c -k --keepParent "$app" "$archive"
    expected="$(shasum -a 256 "$archive")"
    printf '%s\n' "${expected%% *}" > "$archive.sha256"
}
changes=(version build architecture checksum license sparkle-license executable signature
    framework helper permissions symlink key feed consent policy policy-type dependency rpath
    archive-version archive-build archive-framework archive-helper archive-key archive-policy
    archive-framework-drift archive-license-drift archive-extra-code staple gatekeeper)
for change in "${changes[@]}"; do
    plist="$app/Contents/Info.plist"
    framework="$app/Contents/Frameworks/Sparkle.framework"
    case "$change" in
        version|archive-version) /usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 0.0.0' "$plist" ;;
        build|archive-build) /usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 1' "$plist" ;;
        architecture) export FIXTURE_ARCH=x86_64 ;;
        checksum) printf 'bad-checksum\n' > "$archive.sha256" ;;
        license|archive-license-drift) printf 'Different license\n' > "$app/Contents/Resources/licenses/libaom-LICENSE.txt" ;;
        sparkle-license) rm "$app/Contents/Resources/licenses/Sparkle-LICENSE.txt" ;;
        executable) printf '#!/usr/bin/env bash\nexit 1\n# fixture rpath removed\n' > "$app/Contents/MacOS/conv3rt" ;;
        signature) export FIXTURE_BAD_SIGNATURE=1 ;;
        framework|archive-framework) rm -rf "$framework" ;;
        helper|archive-helper) rm "$framework/Versions/B/Autoupdate" ;;
        permissions) chmod -x "$framework/Versions/B/Autoupdate" ;;
        symlink) rm "$framework/Sparkle"; ln -s /usr/bin/true "$framework/Sparkle" ;;
        key|archive-key) /usr/libexec/PlistBuddy -c 'Set :SUPublicEDKey invalid' "$plist" ;;
        feed) /usr/libexec/PlistBuddy -c 'Set :SUFeedURL https://example.com/appcast.xml' "$plist" ;;
        consent) /usr/libexec/PlistBuddy -c 'Add :SUEnableAutomaticChecks bool true' "$plist" ;;
        policy|archive-policy) /usr/libexec/PlistBuddy -c 'Set :SUAutomaticallyUpdate true' "$plist" ;;
        policy-type) /usr/libexec/PlistBuddy -c 'Delete :SUAllowsAutomaticUpdates' -c 'Add :SUAllowsAutomaticUpdates string false' "$plist" ;;
        dependency) export FIXTURE_DEPENDENCY=homebrew ;;
        rpath) export FIXTURE_BAD_RPATH=1 ;;
        archive-framework-drift) printf '\n# Changed helper\n' >> "$framework/Versions/B/Autoupdate" ;;
        archive-extra-code) printf 'Extra code\n' > "$framework/Versions/B/unexpected.dylib" ;;
        staple|gatekeeper) export FIXTURE_ASSESSMENT_FAILURE=1 ;;
    esac
    if [[ "$change" == archive-* ]]; then
        rearchive
        rm -rf "$app"
        ditto -x -k "$TEMP/good.zip" "$folder"
    fi
    if [[ "$change" == staple || "$change" == gatekeeper ]]; then
        # Fail only selected service; other service remains valid fixture.
        tool=xcrun
        [[ "$change" != gatekeeper ]] || tool=spctl
        printf '#!/usr/bin/env bash\nexit 1\n' > "$TOOLS/$tool"
        unset FIXTURE_ASSESSMENT_FAILURE
        if bash "$FIXTURE/scripts/verify-release.sh" "$app" 9.8.7 arm64 release 42 > "$TEMP/verify.log" 2>&1; then fail "Release verifier accepted broken $change."; fi
        printf '#!/usr/bin/env bash\nexit "${FIXTURE_ASSESSMENT_FAILURE:-0}"\n' > "$TOOLS/$tool"
    elif run_verifier; then
        fail "Release verifier accepted broken $change."
    fi
    restore_package
    printf 'PASS release verifier rejects broken %s\n' "$change"
done
run_verifier
printf 'PASS development verifier after fixture restoration\n'

# Optional CLI smoke uses real Mach-O tools and signing, never main Swift builds.
if [[ "${PACKAGING_REAL_SPARKLE:-0}" == 1 ]]; then
    export PATH="$ORIGINAL_PATH"
    unset CODESIGN_IDENTITY FIXTURE_CODECS FIXTURE_ARCH
    source_sparkle="${SPARKLE_ROOT:-$ROOT/.build/artifacts/sparkle/Sparkle}"
    [[ -d "$source_sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" ]] || fail 'Real Sparkle smoke requires resolved official artifact.'
    ditto "$source_sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$FRAMEWORK"
    cp "$source_sparkle/LICENSE" "$SPARKLE/LICENSE"
    REAL_TOOLS="$TEMP/real-tools"
    mkdir -p "$REAL_TOOLS"
    # Substitute only SwiftPM; clang, signing, archive and verifier stay real.
    cat > "$REAL_TOOLS/swift" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ " $* " == *" --show-bin-path "* ]]; then
    printf '%s\n' "$PWD/fake-build"
fi
EOF
    chmod +x "$REAL_TOOLS/swift"
    export PATH="$REAL_TOOLS:$PATH"
    architecture="$(uname -m)"
    mkdir -p "$FIXTURE/fake-build"
    printf 'int main(void) { return 0; }\n' | /usr/bin/clang -x c - -arch "$architecture" \
        -mmacosx-version-min=14.0 -F "$FRAMEWORK/.." -framework Sparkle \
        -Wl,-rpath,@executable_path/../Frameworks -Wl,-rpath,"$FRAMEWORK/.." \
        -o "$FIXTURE/fake-build/conv3rt"
    bash "$FIXTURE/scripts/package.sh" "$architecture" 9.8.7 42 > "$TEMP/real-package.log" 2>&1 || { /bin/cat "$TEMP/real-package.log"; exit 1; }
    printf 'PASS real official Sparkle framework, Mach-O, ad-hoc signatures: %s\n' "$architecture"
fi
