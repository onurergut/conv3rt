#!/usr/bin/env bash
# Builds libavif (with its aom encoder and libyuv, fetched via FetchContent) as
# a static library for one architecture.
# Output: ThirdParty/avif-lib/<arch>/*.a + headers under avif-lib/include.
#
# Not committed (the sources and build output are git-ignored). Run before
# `swift build` to enable AVIF writing; without it, AVIF is simply not an output
# target (and AVIF tests skip).
#
# NOTE: building libaom from source is slow (roughly 10-20 minutes per arch).
# Run this in the background and poll the log.
set -euo pipefail

ARCH="${1:-$(uname -m)}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/ThirdParty/avif-src"
BUILD="$ROOT/ThirdParty/avif-build-$ARCH"
OUT="$ROOT/ThirdParty/avif-lib/$ARCH"

if [ ! -d "$SRC" ]; then
    echo "Cloning libavif v1.1.1 into $SRC ..."
    git clone --recursive --depth 1 -b v1.1.1 \
        https://github.com/AOMediaCodec/libavif "$SRC"
fi

# aom derives its target CPU from the HOST by default, so cross-building to a
# different arch (e.g. x86_64 on an arm64 Mac) wrongly enables NEON/SSE sources
# for the wrong target. Force it explicitly.
case "$ARCH" in
    x86_64) AOM_CPU="x86_64" ;;
    arm64)  AOM_CPU="arm64" ;;
    *)      AOM_CPU="$ARCH" ;;
esac

echo "==> Configuring libavif ($ARCH, static, aom encoder via FetchContent) ..."
cmake -S "$SRC" -B "$BUILD" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew:/usr/local \
    -DAOM_TARGET_CPU="$AOM_CPU" \
    -DBUILD_SHARED_LIBS=OFF \
    -DAVIF_CODEC_AOM=LOCAL \
    -DAVIF_CODEC_DAV1D=OFF \
    -DAVIF_LIBYUV=LOCAL \
    -DAVIF_BUILD_APPS=OFF \
    -DBUILD_TESTING=OFF \
    -DAVIF_BUILD_TESTS=OFF \
    -DAVIF_ENABLE_WERROR=OFF

echo "==> Building (this is the slow aom step) ..."
cmake --build "$BUILD" --config Release -j"$(sysctl -n hw.ncpu)"

mkdir -p "$OUT"
# Collect every static lib produced (libavif.a, libaom.a, libyuv.a).
find "$BUILD" -name '*.a' -exec cp {} "$OUT"/ \;
echo "==> Static libraries in $OUT:"
ls -1 "$OUT"

# libavif's public headers (include/avif/*.h) are shipped next to the libs so
# the SwiftPM target can find them; they are not generated.
if [ -d "$SRC/include" ]; then
    mkdir -p "$ROOT/ThirdParty/avif-lib/include"
    cp -R "$SRC/include/." "$ROOT/ThirdParty/avif-lib/include/"
fi

# If both architectures are built, produce a fat set for the SwiftPM target.
OTHER="x86_64"; [ "$ARCH" = "x86_64" ] && OTHER="arm64"
if [ -d "$ROOT/ThirdParty/avif-lib/$OTHER" ]; then
    FAT="$ROOT/ThirdParty/avif-lib/fat"
    mkdir -p "$FAT"
    for lib in "$OUT"/*.a; do
        base="$(basename "$lib")"
        if [ -f "$ROOT/ThirdParty/avif-lib/$OTHER/$base" ]; then
            lipo -create "$lib" "$ROOT/ThirdParty/avif-lib/$OTHER/$base" -output "$FAT/$base"
        else
            cp "$lib" "$FAT/$base"
        fi
    done
    echo "==> Fat libraries in $FAT:"
    ls -1 "$FAT"
fi
