#!/bin/sh
# SPDX-License-Identifier: MIT
# Builds libphxdec_hevc.dylib (the VideoToolbox decoder: H.264, HEVC, AV1), the test loader phxdec_inject.dylib and the
# in-process test tool vtdec_test, x86_64, ad-hoc signed.
# Usage: FFMPEG_PREFIX=<dir> VULKAN_HEADERS=<dir>/include [OUT=<dir>] ./build.sh
# FFMPEG_PREFIX = install prefix of FFmpeg n7.1 + ../ffmpeg/patches built as libavcodec_phx / libavutil_phx (../build.sh).
# Adapted from Vermilion src/video-decoder/build.sh (MIT).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$HERE/../.." && pwd)
FF=${FFMPEG_PREFIX:?set FFMPEG_PREFIX}; VKH=${VULKAN_HEADERS:?set VULKAN_HEADERS}; OUT=${OUT:-$HERE/build}
PFX="-ffile-prefix-map=$ROOT=/nullarc -fdebug-prefix-map=$ROOT=/nullarc -ffile-prefix-map=$HOME=/build -fdebug-prefix-map=$HOME=/build"
CC="xcrun clang -arch x86_64 -mmacosx-version-min=13.0 -O2 $PFX"
mkdir -p "$OUT"
$CC -Wall -dynamiclib -fvisibility=hidden -install_name @loader_path/libphxdec_hevc.dylib -I"$FF/include" -I"$VKH" \
  "$HERE/phxdec_hevc.c" "$HERE/phxdec_copy.c" -o "$OUT/libphxdec_hevc.dylib" \
  -L"$FF/lib" -lavcodec_phx -lavutil_phx \
  -framework CoreFoundation -framework CoreMedia -framework CoreVideo -framework IOSurface -framework VideoToolbox
cp "$FF/lib/libavcodec_phx.61.dylib" "$FF/lib/libavutil_phx.59.dylib" "$OUT/"
$CC -Wall -dynamiclib "$HERE/phxdec_inject.c" -o "$OUT/phxdec_inject.dylib"
$CC -fobjc-arc "$HERE/vtdec_test.m" -o "$OUT/vtdec_test" \
  -framework Foundation -framework AVFoundation -framework Metal -framework CoreMedia -framework CoreVideo \
  -framework IOSurface -framework VideoToolbox
for f in "$OUT"/*.dylib "$OUT/vtdec_test"; do codesign -fs - "$f"; done
echo "built $OUT"
