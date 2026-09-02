#!/usr/bin/env bash
# Builds a standalone ffmpeg executable for Android arm64-v8a with OpenSSL/TLS
# (HTTPS) support, MediaCodec/JNI support, and drops it in place as libffmpeg.so
# for the PojavLauncherTeam/FFmpegPlugin project structure.
#
# Requires network access. Intended to run in CI (GitHub Actions) or on a
# Linux box with: clang toolchain deps (git, curl, make, perl, pkg-config).
#
# Usage:
#   NDK_VERSION=r27c API_LEVEL=24 ./build-ffmpeg-android.sh
#
# Output:
#   ./out/libffmpeg.so    <- rename target, standalone ELF executable

set -euo pipefail

NDK_VERSION="${NDK_VERSION:-r27c}"
API_LEVEL="${API_LEVEL:-24}"          # matches ZL2/PojavLauncher min supported API
ARCH="arm64-v8a"
TARGET_TRIPLE="aarch64-linux-android"
OPENSSL_VERSION="${OPENSSL_VERSION:-1.1.1w}"
FFMPEG_VERSION="${FFMPEG_VERSION:-9.0}"

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
# 3. ffmpeg 9.0 (static, standalone executable, HTTPS & MediaCodec enabled)
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
  --pkg-config=pkg-config \
  --pkg-config-flags="--static" \
  --enable-openssl \
  --enable-mediacodec \
  --enable-jni \
  --enable-protocol=https,tls,http,file,pipe,rtmp,rtsp \
  --enable-nonfree \
  --disable-doc \
  --disable-debug \
  --extra-cflags="-I$OPENSSL_PREFIX/include" \
  --extra-ldflags="-L$OPENSSL_PREFIX/lib -static-libstdc++" \
  --extra-libs="-lssl -lcrypto -ldl"

echo "==> Building ffmpeg (this takes a while)"
make -j"$(nproc)"

cp ffmpeg "$OUT/libffmpeg.so"
"$STRIP" "$OUT/libffmpeg.so"

echo "==> Verifying it's a real executable ELF, not a shared object"
file "$OUT/libffmpeg.so"

echo "==> Done. Standalone executable (renamed) at: $OUT/libffmpeg.so"
echo "    Copy this into: app/src/main/jniLibs/arm64-v8a/libffmpeg.so"
echo "    in your fork of https://github.com/PojavLauncherTeam/FFmpegPlugin"
