#!/usr/bin/env bash
# Builds a standalone ffmpeg executable for Android arm64-v8a with OpenSSL/TLS
# (HTTPS) support, MediaCodec/JNI support, and drops it in place as libffmpeg.so

set -euo pipefail

NDK_VERSION="${NDK_VERSION:-r27c}"
API_LEVEL="${API_LEVEL:-24}"
ARCH="arm64-v8a"
TARGET_TRIPLE="aarch64-linux-android"
OPENSSL_VERSION="${OPENSSL_VERSION:-1.1.1w}"
FFMPEG_VERSION="${FFMPEG_VERSION:-9.0.1}"

ROOT="$(pwd)"
BUILD="$ROOT/build"
OUT="$ROOT/out"
mkdir -p "$BUILD" "$OUT"

# ---------------------------------------------------------------------------
# 1. Android NDK
# ---------------------------------------------------------------------------
if [ -z "${ANDROID_NDK_HOME:-}" ]; then
  echo "==> Downloading Android NDK $NDK_VERSION"
  cd "$BUILD"
  if [ ! -d "android-ndk-${NDK_VERSION}" ]; then
    curl -L -o ndk.zip "https://dl.google.com/android/repository/android-ndk-${NDK_VERSION}-linux.zip"
    unzip -q ndk.zip
    rm ndk.zip
  fi
  export ANDROID_NDK_HOME="$BUILD/android-ndk-${NDK_VERSION}"
fi
echo "Using NDK at $ANDROID_NDK_HOME"

TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64"
export CC="$TOOLCHAIN/bin/${TARGET_TRIPLE}${API_LEVEL}-clang"
export CXX="$TOOLCHAIN/bin/${TARGET_TRIPLE}${API_LEVEL}-clang++"
export AR="$TOOLCHAIN/bin/llvm-ar"
export RANLIB="$TOOLCHAIN/bin/llvm-ranlib"
export STRIP="$TOOLCHAIN/bin/llvm-strip"
export NM="$TOOLCHAIN/bin/llvm-nm"
export PATH="$TOOLCHAIN/bin:$PATH"

# ---------------------------------------------------------------------------
# 2. OpenSSL (static, for TLS/HTTPS support in ffmpeg)
# ---------------------------------------------------------------------------
cd "$BUILD"
if [ ! -d "openssl-${OPENSSL_VERSION}" ]; then
  echo "==> Downloading OpenSSL $OPENSSL_VERSION"
  curl -L -o openssl.tar.gz "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz"
  tar xf openssl.tar.gz
  rm openssl.tar.gz
fi
cd "openssl-${OPENSSL_VERSION}"

OPENSSL_PREFIX="$BUILD/openssl-install"
if [ ! -f "$OPENSSL_PREFIX/lib/libssl.a" ]; then
  echo "==> Building OpenSSL for android-arm64"
  ./Configure android-arm64 \
    -D__ANDROID_API__="$API_LEVEL" \
    no-shared no-tests \
    --prefix="$OPENSSL_PREFIX" \
    -static
  make -j"$(nproc)"
  make install_sw
fi

# ---------------------------------------------------------------------------
# 3. ffmpeg 9.0.1 (static, standalone executable, HTTPS & MediaCodec enabled)
# ---------------------------------------------------------------------------
cd "$BUILD"
if [ ! -d "ffmpeg-${FFMPEG_VERSION}" ]; then
  echo "==> Downloading ffmpeg $FFMPEG_VERSION"
  curl -L -o ffmpeg.tar.xz "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"
  tar xf ffmpeg.tar.xz
  rm ffmpeg.tar.xz
fi
cd "ffmpeg-${FFMPEG_VERSION}"

export PKG_CONFIG_LIBDIR="$OPENSSL_PREFIX/lib/pkgconfig"
SYSROOT="$TOOLCHAIN/sysroot"

echo "==> Configuring ffmpeg"
./configure \
  --prefix="$BUILD/ffmpeg-install" \
  --target-os=android \
  --arch=aarch64 \
  --cpu=armv8-a \
  --cc="$CC" \
  --cxx="$CXX" \
  --ar="$AR" \
  --ranlib="$RANLIB" \
  --strip="$STRIP" \
  --nm="$NM" \
  --sysroot="$SYSROOT" \
  --enable-cross-compile \
  --enable-static \
  --disable-shared \
  --enable-jni \
  --enable-mediacodec \
  --pkg-config=pkg-config \
  --pkg-config-flags="--static" \
  --enable-openssl \
  --enable-protocol=https,tls,http,file,pipe,rtmp,rtsp \
  --enable-nonfree \
  --disable-doc \
  --disable-debug \
  --extra-cflags="-I$OPENSSL_PREFIX/include" \
  --extra-ldflags="-L$OPENSSL_PREFIX/lib -static-libstdc++" \
  --extra-libs="-lssl -lcrypto -ldl"

echo "==> Verifying configured FFmpeg features"
require_config() {
  local symbol="$1"
  if grep -Eq "^[[:space:]]*#define[[:space:]]+${symbol}[[:space:]]+1[[:space:]]*$" config.h 2>/dev/null || \
     grep -Eq "^${symbol}[[:space:]]*=[[:space:]]*(yes|1)[[:space:]]*$" config.mak 2>/dev/null; then
    echo "  OK: $symbol"
  else
    echo "  MISSING: $symbol"
    return 1
  fi
}

require_config CONFIG_JNI
require_config CONFIG_MEDIACODEC
require_config CONFIG_OPENSSL
require_config CONFIG_HTTPS_PROTOCOL
require_config CONFIG_PIPE_PROTOCOL
require_config CONFIG_PCM_S16LE_MUXER

echo "==> Building ffmpeg"
make -j"$(nproc)"

cp ffmpeg "$OUT/libffmpeg.so"
"$STRIP" "$OUT/libffmpeg.so"

echo "==> Verifying executable ELF format"
file "$OUT/libffmpeg.so"
readelf -h "$OUT/libffmpeg.so" | grep -q 'AArch64'
test -x "$OUT/libffmpeg.so"
"$OUT/libffmpeg.so" -hide_banner -muxers 2>/dev/null | grep -q 'E.*rawvideo'
"$OUT/libffmpeg.so" -hide_banner -muxers 2>/dev/null | grep -q 'E.*s16le'
