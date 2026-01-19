#!/bin/sh

# ============================================================================
# 脚本用途：下载并编译适用于 iOS 的 x264 静态库
# 依赖工具：yasm
# ============================================================================

# 源码配置
X264_REPO="https://code.videolan.org/videolan/x264.git"
# 使用 master 分支或者指定 commit/tag
X264_VERSION="master" 

# 输出目录
FAT="fat-x264"
SCRATCH="scratch-x264"
THIN=`pwd`"/thin-x264"

# iOS 配置
DEPLOYMENT_TARGET="9.0"
ARCHS="arm64 x86_64"

# ====================
# 检查依赖
# ====================
if [ ! `which yasm` ]; then
    echo "❌ Error: yasm not found. Please install via 'brew install yasm'"
    exit 1
fi

if [ ! -d "x264" ]; then
    echo "⬇️  Cloning x264..."
    git clone $X264_REPO x264 || exit 1
else
    echo "✅ x264 source found."
fi

CWD=`pwd`

# ====================
# 编译循环
# ====================
for ARCH in $ARCHS
do
    echo "----------------------------------------"
    echo "🏗  Building x264 for $ARCH..."
    echo "----------------------------------------"

    mkdir -p "$SCRATCH/$ARCH"
    cd "$SCRATCH/$ARCH"

    if [ "$ARCH" = "arm64" ]; then
        PLATFORM="iPhoneOS"
        HOST="aarch64-apple-darwin"
        XARCH="-arch aarch64"
    elif [ "$ARCH" = "x86_64" ]; then
        PLATFORM="iPhoneSimulator"
        HOST="x86_64-apple-darwin"
        XARCH="-arch x86_64"
    fi

    XCRUN_SDK=`echo $PLATFORM | tr '[:upper:]' '[:lower:]'`
    SYSROOT=`xcrun -sdk $XCRUN_SDK --show-sdk-path`
    CC="xcrun -sdk $XCRUN_SDK clang"
    
    CFLAGS="-arch $ARCH -mios-version-min=$DEPLOYMENT_TARGET -fembed-bitcode -isysroot $SYSROOT"
    if [ "$ARCH" = "x86_64" ]; then
        CFLAGS="-arch $ARCH -mios-simulator-version-min=$DEPLOYMENT_TARGET -fembed-bitcode -isysroot $SYSROOT"
    fi

    # 运行 Configure
    if [ "$ARCH" = "x86_64" ]; then
        # 模拟器架构禁用 ASM 以避开复杂的汇编器检测失败问题
        $CWD/x264/configure \
            --host=$HOST \
            --enable-static \
            --enable-pic \
            --disable-cli \
            --disable-asm \
            --prefix="$THIN/$ARCH" \
            --extra-cflags="$CFLAGS" \
            --extra-ldflags="$CFLAGS" || exit 1
    else
        $CWD/x264/configure \
            --host=$HOST \
            --enable-static \
            --enable-pic \
            --disable-cli \
            --prefix="$THIN/$ARCH" \
            --extra-cflags="$CFLAGS" \
            --extra-asflags="$CFLAGS" \
            --extra-ldflags="$CFLAGS" || exit 1
    fi

    make -j4 install || exit 1
    cd $CWD
done

# ====================
# 合并库
# ====================
echo "----------------------------------------"
echo "📦 Creating Fat Library..."
echo "----------------------------------------"
mkdir -p "$FAT/lib"
mkdir -p "$FAT/include"

LIPO_ARGS=""
for ARCH in $ARCHS
do
    LIPO_ARGS="$LIPO_ARGS $THIN/$ARCH/lib/libx264.a"
done

lipo -create $LIPO_ARGS -output "$FAT/lib/libx264.a" || exit 1
cp -r $THIN/arm64/include/* "$FAT/include/"

echo "✅ Done! x264 library is in: $FAT"
