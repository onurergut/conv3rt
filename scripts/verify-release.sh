#!/usr/bin/env bash
set -euo pipefail

APP="${1:?usage: verify-release.sh <app> <version> <arm64|x86_64> [--development] [build-number]}"
VERSION="${2:?version required}"
ARCH="${3:?architecture required}"
MODE="${4:-release}"
BUILD_NUMBER="${5:-2}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
case "$ARCH" in
    arm64) ARCH_NAME=apple-silicon ;;
    x86_64) ARCH_NAME=intel ;;
    *) printf 'Unsupported architecture: %s\n' "$ARCH" >&2; exit 1 ;;
esac
case "$MODE" in
    release|--development) ;;
    *) printf 'Unknown verification mode: %s\n' "$MODE" >&2; exit 1 ;;
esac
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || { printf 'Invalid build number: %s\n' "$BUILD_NUMBER" >&2; exit 1; }
PARENT="$(cd "$(dirname "$APP")" && pwd)"
APP="$PARENT/$(basename "$APP")"
ARCHIVE="$PARENT/conv3rt-$VERSION-$ARCH_NAME.zip"
PLIST="$APP/Contents/Info.plist"
BIN="$APP/Contents/MacOS/conv3rt"

fail() { printf '%s\n' "$*" >&2; exit 1; }
require_file() { [[ -s "$1" ]] || fail "Missing or empty: $1"; }
require_inside() {
    local resolved
    resolved="$(/bin/realpath "$1")" || fail "Cannot resolve: $1"
    [[ "$resolved" == "$BUNDLE_ROOT/"* ]] || fail "Path escapes bundle: $1"
}
plist_string() { plutil -extract "$2" raw -expect string "$1"; }
KEY_FILE="$ROOT/Resources/update-public-key.txt"
require_file "$KEY_FILE"
PUBLIC_KEY="$(< "$KEY_FILE")"
[[ "$PUBLIC_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]] || fail 'Invalid trusted Ed25519 public key'

# Parse only dependency rows; framework ID rows are safe to validate as well.
read_libraries() {
    local output
    output="$(otool -L "$1")" || fail "Cannot inspect libraries: $1"
    printf '%s\n' "$output" | /usr/bin/awk '
        /^[[:space:]]+/ && / \(compatibility version / {
            sub(/^[[:space:]]+/, ""); sub(/ \(compatibility version .*/, ""); print
        }
    '
}
read_rpaths() {
    local output
    output="$(otool -l "$1")" || fail "Cannot inspect load commands: $1"
    printf '%s\n' "$output" | /usr/bin/awk '
        $1 == "cmd" && $2 == "LC_RPATH" { pending=1; next }
        pending && $1 == "path" { sub(/^[[:space:]]*path /, ""); sub(/ \(offset [0-9]+\)$/, ""); print; pending=0 }
    '
}
is_system_path() {
    case "$1" in
        /usr/lib/*|/System/Library/*)
            [[ "$1" != *'/../'* && "$1" != *'/./'* && "$1" != */.. && "$1" != */. ]] ;;
        *) return 1 ;;
    esac
}
expand_path() {
    case "$1" in
        @executable_path) printf '%s\n' "$3" ;;
        @executable_path/*) printf '%s/%s\n' "$3" "${1#@executable_path/}" ;;
        @loader_path) printf '%s\n' "$(dirname "$2")" ;;
        @loader_path/*) printf '%s/%s\n' "$(dirname "$2")" "${1#@loader_path/}" ;;
        /usr/lib/*|/System/Library/*) printf '%s\n' "$1" ;;
        *) fail "Unsafe runtime path in $2: $1" ;;
    esac
}
verify_macho() {
    local image="$1" executable_dir="$2" rpaths libraries path expanded library candidate found
    local search_paths=()
    require_file "$image"
    require_inside "$image"
    [[ -x "$image" ]] || fail "Missing executable permission: $image"
    rpaths="$(read_rpaths "$image")"
    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        expanded="$(expand_path "$path" "$image" "$executable_dir")"
        if ! is_system_path "$expanded"; then
            [[ -d "$expanded" ]] || fail "Missing runtime search directory: $expanded"
            require_inside "$expanded"
        fi
        search_paths+=("$expanded")
    done <<< "$rpaths"
    # Only in-process framework loads inherit the host's run-path stack.
    if [[ "${3:-false}" == true ]]; then
        for path in "${MAIN_RPATHS[@]-}"; do
            [[ -n "$path" ]] || continue
            search_paths+=("$path")
        done
    fi
    libraries="$(read_libraries "$image")"
    [[ -n "$libraries" ]] || fail "No linked libraries found: $image"
    while IFS= read -r library; do
        if is_system_path "$library"; then continue; fi
        case "$library" in
            @rpath/*)
                found=false
                for path in "${search_paths[@]-}"; do
                    [[ -n "$path" ]] || continue
                    candidate="$path/${library#@rpath/}"
                    if is_system_path "$candidate"; then
                        found=true
                        break
                    elif [[ -s "$candidate" ]]; then
                        require_inside "$candidate"
                        found=true
                        break
                    fi
                done
                [[ "$found" == true ]] || fail "Unresolved bundled library in $image: $library"
                ;;
            @loader_path/*|@executable_path/*)
                candidate="$(expand_path "$library" "$image" "$executable_dir")"
                require_file "$candidate"
                require_inside "$candidate"
                ;;
            *) fail "External linked library in $image: $library" ;;
        esac
    done <<< "$libraries"
}
verify_bundle() {
    local bundle="$1" plist="$1/Contents/Info.plist" bin="$1/Contents/MacOS/conv3rt"
    local flag framework version name helper path architectures main_paths
    BUNDLE_ROOT="$(/bin/realpath "$bundle")"
    require_file "$plist"
    require_inside "$plist"
    [[ "$(plist_string "$plist" CFBundleShortVersionString)" == "$VERSION" ]] || fail "Version mismatch: $bundle"
    [[ "$(plist_string "$plist" CFBundleVersion)" == "$BUILD_NUMBER" ]] || fail "Build number mismatch: $bundle"
    [[ "$(plist_string "$plist" SUPublicEDKey)" == "$PUBLIC_KEY" ]] || fail "Update public key mismatch: $bundle"
    [[ "$(plist_string "$plist" SUFeedURL)" == "https://raw.githubusercontent.com/onurergut/conv3rt/main/updates/appcast-$ARCH.xml" ]] || fail "Update feed mismatch: $bundle"
    for flag in SUAllowsAutomaticUpdates SUAutomaticallyUpdate SUEnableSystemProfiling SUSendProfileInfo; do
        [[ "$(plutil -extract "$flag" raw -expect bool "$plist")" == false ]] || fail "Update policy must be boolean false ($flag): $bundle"
    done
    if /usr/libexec/PlistBuddy -c 'Print :SUEnableAutomaticChecks' "$plist" > /dev/null 2>&1; then
        fail "Automatic update checks must await native consent: $bundle"
    fi
    [[ -x "$bin" ]] || fail "Missing executable: $bin"
    require_inside "$bin"
    [[ "$(lipo -archs "$bin")" == "$ARCH" ]] || fail "Executable architecture differs from $ARCH: $bundle"
    require_file "$bundle/Contents/Resources/THIRD_PARTY_NOTICES.txt"
    require_file "$bundle/Contents/Resources/conv3rt.icns"
    for name in "${licenses[@]}"; do
        require_file "$bundle/Contents/Resources/licenses/$name.txt"
        require_inside "$bundle/Contents/Resources/licenses/$name.txt"
    done
    framework="$bundle/Contents/Frameworks/Sparkle.framework"
    version="$framework/Versions/B"
    [[ -d "$version" ]] || fail "Required Sparkle framework missing: $framework"
    [[ -L "$framework/Versions/Current" && "$(readlink "$framework/Versions/Current")" == B ]] || fail 'Sparkle current-version symlink missing or altered'
    for name in Sparkle Autoupdate Resources Updater.app XPCServices; do
        [[ -L "$framework/$name" && "$(readlink "$framework/$name")" == "Versions/Current/$name" ]] || fail "Sparkle symlink missing or altered: $name"
        require_inside "$framework/$name"
    done
    require_file "$version/Resources/Info.plist"
    require_inside "$version/Resources/Info.plist"
    [[ "$(plist_string "$version/Resources/Info.plist" CFBundleShortVersionString)" == 2.10.0 ]] || fail 'Sparkle framework must be version 2.10.0'
    MAIN_RPATHS=()
    main_paths="$(read_rpaths "$bin")"
    [[ "$main_paths" == *'@executable_path/../Frameworks'* ]] || fail 'Missing bundled-framework runtime search path'
    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        path="$(expand_path "$path" "$bin" "$bundle/Contents/MacOS")"
        if ! is_system_path "$path"; then
            [[ -d "$path" ]] || fail "Missing runtime search directory: $path"
            require_inside "$path"
        fi
        MAIN_RPATHS+=("$path")
    done <<< "$main_paths"
    [[ "$(read_libraries "$bin")" == *'@rpath/Sparkle.framework/Versions/B/Sparkle'* ]] || fail 'Executable must link bundled Sparkle through @rpath'
    verify_macho "$bin" "$bundle/Contents/MacOS"
    for name in Sparkle Autoupdate; do
        architectures="$(lipo -archs "$version/$name")"
        [[ "$architectures" == 'x86_64 arm64' || "$architectures" == 'arm64 x86_64' ]] || fail "Sparkle helper must be universal: $name"
        if [[ "$name" == Sparkle ]]; then
            verify_macho "$version/$name" "$bundle/Contents/MacOS" true
        else
            verify_macho "$version/$name" "$version"
        fi
    done
    for helper in Updater.app XPCServices/Downloader.xpc XPCServices/Installer.xpc; do
        name="$(basename "${helper%.*}")"
        require_file "$version/$helper/Contents/Info.plist"
        require_inside "$version/$helper/Contents/Info.plist"
        path="$version/$helper/Contents/MacOS/$name"
        [[ -x "$path" ]] || fail "Sparkle helper missing or not executable: $path"
        architectures="$(lipo -archs "$path")"
        [[ "$architectures" == 'x86_64 arm64' || "$architectures" == 'arm64 x86_64' ]] || fail "Sparkle helper must be universal: $helper"
        verify_macho "$path" "$(dirname "$path")"
    done
    codesign --verify --deep --strict --verbose=2 "$bundle"
}

require_file "$PLIST"
[[ -x "$BIN" ]] || fail "Missing executable: $BIN"
licenses=(libwebp-COPYING libwebp-PATENTS Sparkle-LICENSE)
SYMBOLS="$(nm -g "$BIN")"
if [[ "$SYMBOLS" == *"_conv3rt_jxl_encode_rgba"* ]]; then
    licenses+=(libjxl-LICENSE libjxl-PATENTS highway-LICENSE brotli-LICENSE lcms2-LICENSE libpng-LICENSE zlib-LICENSE)
fi
if [[ "$SYMBOLS" == *"_conv3rt_avif_encode_rgba"* ]]; then
    licenses+=(libavif-LICENSE libaom-LICENSE libaom-PATENTS libaom-fastfeat-LICENSE libaom-vector-LICENSE libaom-x86inc-LICENSE libyuv-LICENSE libyuv-PATENTS)
fi
verify_bundle "$APP"
"$BIN" --dump-capabilities > /dev/null
require_file "$ARCHIVE"
require_file "$ARCHIVE.sha256"
DIGEST="$(shasum -a 256 "$ARCHIVE")"
[[ "$(< "$ARCHIVE.sha256")" == "${DIGEST%% *}" ]] || fail 'Archive SHA-256 mismatch'

TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
ditto -x -k "$ARCHIVE" "$TEMP"
ARCHIVED_APP="$TEMP/conv3rt.app"
verify_bundle "$ARCHIVED_APP"
cpmatch() { cmp "$1" "$2" || fail "Archive differs from bundle: $1"; }
cpmatch "$PLIST" "$ARCHIVED_APP/Contents/Info.plist"
cpmatch "$BIN" "$ARCHIVED_APP/Contents/MacOS/conv3rt"
cpmatch "$APP/Contents/Resources/THIRD_PARTY_NOTICES.txt" "$ARCHIVED_APP/Contents/Resources/THIRD_PARTY_NOTICES.txt"
cpmatch "$APP/Contents/Resources/conv3rt.icns" "$ARCHIVED_APP/Contents/Resources/conv3rt.icns"
for license in "${licenses[@]}"; do
    cpmatch "$APP/Contents/Resources/licenses/$license.txt" "$ARCHIVED_APP/Contents/Resources/licenses/$license.txt"
done
diff -rq "$APP/Contents/Frameworks" "$ARCHIVED_APP/Contents/Frameworks" || fail 'Archive frameworks differ from bundle'

if [[ "$MODE" == release ]]; then
    xcrun stapler validate "$ARCHIVED_APP"
    spctl -a -vvv -t exec "$ARCHIVED_APP"
    xcrun stapler validate "$APP"
    spctl -a -vvv -t exec "$APP"
    printf 'Release verification passed: %s\n' "$ARCHIVE"
else
    printf 'Development package verified; notarization and Gatekeeper not checked: %s\n' "$ARCHIVE"
fi
