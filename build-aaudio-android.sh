#!/usr/bin/env bash
# Builds libaaudio_sink.so for arm64-v8a
set -euo pipefail

NDK_VERSION="${NDK_VERSION:-r27c}"
API_LEVEL="${API_LEVEL:-26}"   # AAudio requires API 26+

ROOT="$(pwd)"
OUT="$ROOT/out"
BUILD="$ROOT/build/aaudio"
mkdir -p "$OUT" "$BUILD"

# NDK setup (same as your ffmpeg script)
TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64"
export CC="$TOOLCHAIN/bin/aarch64-linux-android${API_LEVEL}-clang"
export CXX="$TOOLCHAIN/bin/aarch64-linux-android${API_LEVEL}-clang++"
export STRIP="$TOOLCHAIN/bin/llvm-strip"

SYSROOT="$TOOLCHAIN/sysroot"
AAUDIO_HEADER="$SYSROOT/usr/include/aaudio/AAudio.h"

# Write the source inline
cat > "$BUILD/aaudio_sink.cpp" << 'EOF'
#include <aaudio/AAudio.h>
#include <android/log.h>
#include <cstdint>

#define TAG "AAudioSink"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

extern "C" {

void* aaudio_open(int32_t sampleRate, int32_t channelCount) {
    AAudioStreamBuilder* builder = nullptr;
    if (AAudio_createStreamBuilder(&builder) != AAUDIO_OK) return nullptr;
    AAudioStreamBuilder_setSampleRate(builder, sampleRate);
    AAudioStreamBuilder_setChannelCount(builder, channelCount);
    AAudioStreamBuilder_setFormat(builder, AAUDIO_FORMAT_PCM_I16);
    AAudioStreamBuilder_setPerformanceMode(builder, AAUDIO_PERFORMANCE_MODE_LOW_LATENCY);

    AAudioStream* stream = nullptr;
    AAudioStreamBuilder_setSharingMode(builder, AAUDIO_SHARING_MODE_EXCLUSIVE);
    aaudio_result_t r = AAudioStreamBuilder_openStream(builder, &stream);
    if (r != AAUDIO_OK) {
        // Exclusive-mode streams get forcibly disconnected on route/focus changes far more often;
        // shared mode is mixed but far more resilient, so fall back to it instead of failing open.
        LOGE("exclusive open failed: %s, retrying shared", AAudio_convertResultToText(r));
        AAudioStreamBuilder_setSharingMode(builder, AAUDIO_SHARING_MODE_SHARED);
        r = AAudioStreamBuilder_openStream(builder, &stream);
    }
    AAudioStreamBuilder_delete(builder);
    if (r != AAUDIO_OK) { LOGE("open failed: %s", AAudio_convertResultToText(r)); return nullptr; }
    AAudioStream_requestStart(stream);
    return stream;
}

void  aaudio_close(void* h)   { if(!h) return; AAudioStream_requestStop((AAudioStream*)h); AAudioStream_close((AAudioStream*)h); }
int32_t aaudio_write(void* h, const void* data, int32_t frames, int64_t timeoutNs) { return AAudioStream_write((AAudioStream*)h, data, frames, timeoutNs); }
int32_t aaudio_get_timestamp(void* h, int64_t* pos, int64_t* ns) { return AAudioStream_getTimestamp((AAudioStream*)h, CLOCK_MONOTONIC, pos, ns); }
int64_t aaudio_frames_written(void* h) { return AAudioStream_getFramesWritten((AAudioStream*)h); }
int32_t aaudio_pause(void* h)  { return AAudioStream_requestPause((AAudioStream*)h); }
int32_t aaudio_resume(void* h) { return AAudioStream_requestStart((AAudioStream*)h); }
int32_t aaudio_flush(void* h)  { return AAudioStream_requestFlush((AAudioStream*)h); }
int32_t aaudio_buffer_size(void* h) { return AAudioStream_getBufferSizeInFrames((AAudioStream*)h); }

} // extern "C"
EOF

echo "==> Building libaaudio_sink.so"
"$CXX" \
    --sysroot="$SYSROOT" \
    -target aarch64-linux-android${API_LEVEL} \
    -shared -fPIC \
    -O2 -s \
    -o "$BUILD/libaaudio_sink.so" \
    "$BUILD/aaudio_sink.cpp" \
    -laaudio -llog

"$STRIP" "$BUILD/libaaudio_sink.so"
cp "$BUILD/libaaudio_sink.so" "$OUT/libaaudio_sink.so"

echo "==> Done: $OUT/libaaudio_sink.so"
echo "    Copy to: app/src/main/jniLibs/arm64-v8a/libaaudio_sink.so"
