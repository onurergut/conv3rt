#!/usr/bin/env bash
# Builds libjxl as a minimal static library for one architecture.
# Output: ThirdParty/jxl-lib/<arch>/*.a  + headers under jxl-src/lib/include.
#
# Not committed (the sources and build output are git-ignored). Run before
# `swift build` to enable JPEG XL writing; without it, JXL is simply not a
# target (and JXL tests skip).
set -euo pipefail

ARCH="${1:-$(uname -m)}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/ThirdParty/jxl-src"
BUILD="$ROOT/ThirdParty/jxl-build-$ARCH"
OUT="$ROOT/ThirdParty/jxl-lib/$ARCH"

if [ ! -d "$SRC" ]; then
    echo "Cloning libjxl v0.11.2 into $SRC ..."
    git clone --recursive --depth 1 -b v0.11.2 \
        https://github.com/libjxl/libjxl "$SRC"
fi

echo "==> Configuring libjxl ($ARCH, static, minimal, no Homebrew) ..."
cmake -S "$SRC" -B "$BUILD" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew:/usr/local \
    -DCMAKE_IGNORE_PATH=/opt/homebrew:/opt/homebrew/lib:/opt/homebrew/include:/opt/homebrew/opt \
    -DPKG_CONFIG_USE_CMAKE_PREFIX_PATH=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_TESTING=OFF \
    -DJPEGXL_ENABLE_TOOLS=OFF \
    -DJPEGXL_ENABLE_EXAMPLES=OFF \
    -DJPEGXL_ENABLE_BENCHMARK=OFF \
    -DJPEGXL_ENABLE_TESTS=OFF \
    -DJPEGXL_ENABLE_PLUGINS=OFF \
    -DJPEGXL_ENABLE_DOXYGEN=OFF \
    -DJPEGXL_ENABLE_MANPAGES=OFF \
    -DJPEGXL_ENABLE_JNI=OFF \
    -DJPEGXL_ENABLE_VIEWERS=OFF \
    -DJPEGXL_ENABLE_OPENEXR=OFF \
    -DJPEGXL_ENABLE_SKCMS=OFF \
    -DJPEGXL_ENABLE_SJPEG=OFF \
    -DJPEGXL_BUNDLE_LIBPNG=ON \
    -DJPEGXL_FORCE_SYSTEM_BROTLI=OFF \
    -DJPEGXL_FORCE_SYSTEM_HWY=OFF \
    -DJPEGXL_FORCE_SYSTEM_LCMS2=OFF

echo "==> Building ..."
cmake --build "$BUILD" --config Release -j"$(sysctl -n hw.ncpu)"

mkdir -p "$OUT"
find "$BUILD" -name '*.a' -exec cp {} "$OUT"/ \;
echo "==> Static libraries in $OUT:"
ls -1 "$OUT"

# Generated headers (jxl_export.h etc.) live in the build tree; copy them next to
# the source headers so the SwiftPM target can find them.
if [ -d "$BUILD/lib/include" ]; then
    mkdir -p "$ROOT/ThirdParty/jxl-lib/include"
    cp -R "$BUILD/lib/include/." "$ROOT/ThirdParty/jxl-lib/include/"
fi

# If both architectures are built, produce a fat set for the SwiftPM target.
OTHER="x86_64"; [ "$ARCH" = "x86_64" ] && OTHER="arm64"
if [ -d "$ROOT/ThirdParty/jxl-lib/$OTHER" ]; then
    FAT="$ROOT/ThirdParty/jxl-lib/fat"
    mkdir -p "$FAT"
    for lib in "$OUT"/*.a; do
        base="$(basename "$lib")"
        if [ -f "$ROOT/ThirdParty/jxl-lib/$OTHER/$base" ]; then
            lipo -create "$lib" "$ROOT/ThirdParty/jxl-lib/$OTHER/$base" -output "$FAT/$base"
        else
            cp "$lib" "$FAT/$base"
        fi
    done
    echo "==> Fat libraries in $FAT:"
    ls -1 "$FAT"
fi

