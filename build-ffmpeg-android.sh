#!/bin/bash

set -e

# ====================
# 配置部分
# ====================
FF_VERSION="7.1"
SOURCE="ffmpeg-$FF_VERSION"
API_LEVEL=21 # Android 5.0+
OUTPUT_DIR="FFmpeg-Android"
THIN_DIR=`pwd`"/thin-android"
SCRATCH_DIR="scratch-android"

# 要编译的架构
# 常用: arm64-v8a armeabi-v7a
# 可选: x86 x86_64 (模拟器)
ARCHS="arm64-v8a armeabi-v7a"

# ====================
# NDK 检测
# ====================
if [ -z "$ANDROID_NDK_HOME" ]; then
    # 尝试在 macOS 默认 SDK 路径查找
    POSSIBLE_NDK_ROOT="$HOME/Library/Android/sdk/ndk"
    if [ -d "$POSSIBLE_NDK_ROOT" ]; then
        # 获取该目录下版本号最大的目录
        NDK_VER=$(ls -1 "$POSSIBLE_NDK_ROOT" | sort -V | tail -n 1)
        if [ -n "$NDK_VER" ]; then
            export ANDROID_NDK_HOME="$POSSIBLE_NDK_ROOT/$NDK_VER"
            echo "✅ Auto-detected NDK: $ANDROID_NDK_HOME"
        fi
    fi
fi

if [ -z "$ANDROID_NDK_HOME" ]; then
    echo "❌ Error: ANDROID_NDK_HOME is not set."
    echo "   Please set it using: export ANDROID_NDK_HOME=/path/to/your/ndk"
    exit 1
fi

TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64"
if [ ! -d "$TOOLCHAIN" ]; then
    echo "❌ Error: Toolchain not found at $TOOLCHAIN"
    echo "   Check your NDK version/path."
    exit 1
fi

# ====================
# 源码准备
# ====================
if [ ! -r $SOURCE ]; then
    echo "⬇️  Downloading FFmpeg $FF_VERSION..."
    curl -L http://www.ffmpeg.org/releases/$SOURCE.tar.bz2 | tar xj || exit 1
fi

CWD=`pwd`

# ====================
# 编译函数
# ====================
build_android() {
    ARCH=$1
    CPU=$2
    PREFIX=$3
    HOST_TRIPLE=$4
    CROSS_PREFIX=$5
    EXTRA_CFLAGS=$6
    EXTRA_LDFLAGS=$7

    echo "----------------------------------------"
    echo "🏗  Building FFmpeg (Android) for $ARCH..."
    echo "----------------------------------------"

    mkdir -p "$SCRATCH_DIR/$ARCH"
    cd "$SCRATCH_DIR/$ARCH"

    # Android Clang 编译器路径
    CC="$TOOLCHAIN/bin/${HOST_TRIPLE}${API_LEVEL}-clang"
    CXX="$TOOLCHAIN/bin/${HOST_TRIPLE}${API_LEVEL}-clang++"
    AR="$TOOLCHAIN/bin/llvm-ar"
    NM="$TOOLCHAIN/bin/llvm-nm"
    RANLIB="$TOOLCHAIN/bin/llvm-ranlib"
    STRIP="$TOOLCHAIN/bin/llvm-strip"

    if [ ! -f "$CC" ]; then
        echo "❌ Compiler not found: $CC"
        exit 1
    fi

    # FFmpeg Configure
    # 注意：这里移除了部分双引号以避免 shell 解析错误
    # 同时启用了 GPL 以防某些库需要
    $CWD/$SOURCE/configure \
        --target-os=android \
        --prefix=$PREFIX \
        --arch=$CPU \
        --enable-cross-compile \
        --cross-prefix="$TOOLCHAIN/bin/$CROSS_PREFIX-" \
        --cc="$CC" \
        --cxx="$CXX" \
        --ar="$AR" \
        --nm="$NM" \
        --ranlib="$RANLIB" \
        --strip="$STRIP" \
        --sysroot="$TOOLCHAIN/sysroot" \
        --enable-pic \
        --enable-jni \
        --enable-mediacodec \
        --disable-static \
        --enable-shared \
        --disable-doc \
        --disable-programs \
        --disable-avdevice \
        --disable-symver \
        --extra-cflags="-Os -fPIC $EXTRA_CFLAGS" \
        --extra-ldflags="$EXTRA_LDFLAGS" \
        || exit 1

    make -j8 install || exit 1
    cd $CWD
}

# ====================
# 主循环
# ====================

for ARCH in $ARCHS
do
    case $ARCH in
        arm64-v8a)
            build_android "arm64-v8a" "aarch64" "$THIN_DIR/arm64-v8a" "aarch64-linux-android" "aarch64-linux-android" "" ""
            ;; 
        armeabi-v7a)
            build_android "armeabi-v7a" "arm" "$THIN_DIR/armeabi-v7a" "armv7a-linux-androideabi" "arm-linux-androideabi" "-march=armv7-a -mfloat-abi=softfp -mfpu=vfpv3-d16" "-march=armv7-a -Wl,--fix-cortex-a8"
            ;; 
        x86)
            build_android "x86" "x86" "$THIN_DIR/x86" "i686-linux-android" "i686-linux-android" "-march=i686 -mtune=intel -mssse3 -mfpmath=sse -m32" ""
            ;; 
        x86_64)
            build_android "x86_64" "x86_64" "$THIN_DIR/x86_64" "x86_64-linux-android" "x86_64-linux-android" "-march=x86-64 -msse4.2 -mpopcnt -m64" ""
            ;; 
    esac
done

# ====================
# 整理输出 (类似 Android Studio jniLibs 结构)
# ====================
echo "----------------------------------------"
echo "🚀 Organizing Output: $OUTPUT_DIR..."
echo "----------------------------------------"

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

for ARCH in $ARCHS
do
    # 复制 .so 文件
    mkdir -p "$OUTPUT_DIR/jniLibs/$ARCH"
    cp -f "$THIN_DIR/$ARCH/lib/"*.so "$OUTPUT_DIR/jniLibs/$ARCH/"
    
    # 复制头文件 (只需一份，通常各架构相同)
    if [ ! -d "$OUTPUT_DIR/include" ]; then
        cp -R "$THIN_DIR/$ARCH/include" "$OUTPUT_DIR/"
    fi
done

echo "✅ Android build complete!"
echo "   Libraries: $OUTPUT_DIR/jniLibs"
echo "   Headers:   $OUTPUT_DIR/include"