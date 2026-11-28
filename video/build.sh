#!/bin/bash
# SPDX-License-Identifier: MIT
# build.sh: build the VCN video decoder stack from source on the Mac (x86_64, Command Line Tools clang; no Homebrew).
#
#   Mesa  f5cb8ee + mesa/patches (0001-0017 Vermilion's RADV Darwin series, 0018-0020 Phoenix VCN changes)
#         -> a decoder-private libvulkan_radeon.dylib with Vulkan Video (it does not replace the plugin's RADV)
#   FFmpeg n7.1 + ffmpeg/patches -> libavcodec_phx / libavutil_phx (h264, hevc, av1 + their Vulkan hwaccels only)
#   decoder/ -> libphxdec_hevc.dylib (VideoToolbox decoder), phxdec_inject.dylib, vtdec_test
#
# Usage: bash build.sh [WORK=<dir>] [OUT=<dir>]   (defaults: video/work, video/out; about 2 GB and 15-30 minutes)
# Downloads (pinned): python-build-standalone 3.12 (Mesa needs Python >= 3.10, macOS ships 3.9), meson / ninja / mako /
# pyyaml / packaging / cmake from PyPI, glslang 15.1.0, Vulkan-Headers v1.4.368, Mesa, FFmpeg.
# Install the result with install.sh (root).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-$HERE/work}; OUT=${OUT:-$HERE/out}
JOBS=${JOBS:-$(sysctl -n hw.ncpu)}
MESA_BASE=f5cb8ee032adabef599ae892ec4e42d796b84da9
FFMPEG_TAG=n7.1; FFMPEG_COMMIT=b08d7969c550a804a59511c7b83f2dd8cc0499b8
VKH_TAG=v1.4.368; GLSLANG_TAG=15.1.0
PY_URL=https://github.com/astral-sh/python-build-standalone/releases/download/20261124/cpython-3.12.16%2B20261124-x86_64-apple-darwin-install_only.tar.gz
PY_SHA256=ccce24cfd3f56f62561d2c9480fcc567ca3a9bac68450cd73e11aeb631befa1f
GIT="git -c advice.detachedHead=false -c user.name=build -c user.email=build@localhost"

[ "$(uname -m)" = x86_64 ] || { echo "build on the x86_64 Mac (the decoder runs in x86_64 processes there)"; exit 1; }
xcrun -f clang >/dev/null || { echo "install the Command Line Tools: xcode-select --install"; exit 1; }
mkdir -p "$WORK" "$OUT/decoder"; cd "$WORK"
step(){ echo; echo "== $(date '+%T') $*"; }

step "Python 3.12 + build tools"
if [ ! -x python/bin/python3 ]; then
  curl -fL --retry 3 -o py.tgz "$PY_URL"
  echo "$PY_SHA256  py.tgz" | shasum -a 256 -c -
  tar xzf py.tgz && rm py.tgz
fi
[ -x venv/bin/python3 ] || python/bin/python3 -m venv venv
venv/bin/pip install -q meson==1.12.1 ninja==1.13.2 mako==1.4.3 pyyaml==6.0.4 packaging==26.4 cmake==4.4.5
export PATH=$WORK/venv/bin:$WORK/prefix/bin:$PATH

step "glslang $GLSLANG_TAG"
if [ ! -x prefix/bin/glslangValidator ]; then
  [ -d glslang ] || $GIT clone -q --depth 1 --branch $GLSLANG_TAG https://github.com/KhronosGroup/glslang.git
  cmake -S glslang -B glslang/build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$WORK/prefix" \
    -DENABLE_OPT=OFF -DGLSLANG_TESTS=OFF >/dev/null
  ninja -C glslang/build install >/dev/null
fi

step "Vulkan-Headers $VKH_TAG"
[ -d Vulkan-Headers ] || $GIT clone -q --depth 1 --branch $VKH_TAG https://github.com/KhronosGroup/Vulkan-Headers.git

step "Mesa $MESA_BASE + $(ls "$HERE"/mesa/patches/*.patch | wc -l | tr -d ' ') patches"
if [ ! -d mesa/.git ]; then
  mkdir mesa; $GIT -C mesa init -q; $GIT -C mesa remote add origin https://gitlab.freedesktop.org/mesa/mesa.git
  $GIT -C mesa fetch -q --depth 1 origin $MESA_BASE; $GIT -C mesa checkout -q FETCH_HEAD
  $GIT -C mesa am -q "$HERE"/mesa/patches/*.patch
fi
if [ ! -d mesa/build-vcn ]; then
  meson setup mesa/build-vcn mesa --buildtype=release -Dvulkan-drivers=amd -Dgallium-drivers= -Dplatforms= \
    -Dllvm=disabled -Dglx=disabled -Degl=disabled -Dgbm=disabled -Dopengl=false -Dgles1=disabled -Dgles2=disabled \
    -Dxmlconfig=disabled -Dvalgrind=disabled -Dlibunwind=disabled -Dzstd=disabled -Dbuild-tests=false \
    -Dvulkan-layers= -Dtools= -Dvideo-codecs=all >/dev/null
fi
ninja -C mesa/build-vcn -j "$JOBS" >/dev/null
cp mesa/build-vcn/src/amd/vulkan/libvulkan_radeon.dylib "$OUT/libvulkan_radeon_vcn.dylib"

step "FFmpeg $FFMPEG_TAG + $(ls "$HERE"/ffmpeg/patches/*.patch | wc -l | tr -d ' ') patches"
if [ ! -d ffmpeg/.git ]; then
  $GIT clone -q --depth 1 --branch $FFMPEG_TAG https://github.com/FFmpeg/FFmpeg.git ffmpeg
  [ "$(git -C ffmpeg rev-parse HEAD)" = $FFMPEG_COMMIT ] || { echo "FFmpeg $FFMPEG_TAG is not $FFMPEG_COMMIT"; exit 1; }
  $GIT -C ffmpeg am -q "$HERE"/ffmpeg/patches/*.patch
fi
if [ ! -f ffprefix/lib/libavcodec_phx.61.dylib ]; then
  ( cd ffmpeg
    ./configure --prefix="$WORK/ffprefix" --cc=clang --arch=x86_64 --disable-everything --disable-autodetect \
      --disable-programs --disable-doc --disable-static --enable-shared --disable-avdevice --disable-avformat \
      --disable-swscale --disable-swresample --disable-avfilter --disable-postproc --disable-x86asm --enable-pthreads \
      --enable-vulkan --enable-decoder=h264,hevc,av1 --enable-hwaccel=h264_vulkan,hevc_vulkan,av1_vulkan \
      --enable-parser=h264,hevc,av1 --enable-bsf=h264_mp4toannexb,hevc_mp4toannexb,av1_frame_merge \
      --build-suffix=_phx --extra-cflags="-I$WORK/Vulkan-Headers/include -mmacosx-version-min=13.0" \
      --extra-ldflags="-mmacosx-version-min=13.0" >/dev/null
    make -j "$JOBS" >/dev/null && make install >/dev/null )
fi

step "decoder"
FFMPEG_PREFIX="$WORK/ffprefix" VULKAN_HEADERS="$WORK/Vulkan-Headers/include" OUT="$OUT/decoder" sh "$HERE/decoder/build.sh"
# the decoder and FFmpeg find each other next to themselves once installed
FF="$WORK/ffprefix/lib"; D="$OUT/decoder"
install_name_tool -change "$FF/libavcodec_phx.61.dylib" @loader_path/libavcodec_phx.61.dylib \
  -change "$FF/libavutil_phx.59.dylib" @loader_path/libavutil_phx.59.dylib "$D/libphxdec_hevc.dylib" 2>/dev/null
install_name_tool -id @loader_path/libavcodec_phx.61.dylib \
  -change "$FF/libavutil_phx.59.dylib" @loader_path/libavutil_phx.59.dylib "$D/libavcodec_phx.61.dylib" 2>/dev/null
install_name_tool -id @loader_path/libavutil_phx.59.dylib "$D/libavutil_phx.59.dylib" 2>/dev/null
for f in "$D"/*.dylib "$OUT/libvulkan_radeon_vcn.dylib"; do codesign -fs - "$f" 2>/dev/null; done

step "done"
ls -la "$OUT" "$OUT/decoder"
