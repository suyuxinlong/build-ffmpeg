#!/bin/sh

# ============================================================================
# 脚本用途：下载并编译适用于 iOS 的 x265 (HEVC) 静态库
# 依赖工具：cmake, yasm (或 nasm)
# ============================================================================

# x265 版本 (改用 GitHub 镜像以提高下载稳定性)
X265_VERSION="3.4"
SOURCE_URL="https://github.com/videolan/x265/archive/refs/tags/$X265_VERSION.tar.gz"
SOURCE_DIR="x265-$X265_VERSION"

# 输出目录
FAT="fat-x265"
SCRATCH="scratch-x265"
THIN=`pwd`"/thin-x265"

# iOS 部署目标
DEPLOYMENT_TARGET="9.0"

# 架构列表
ARCHS="arm64 x86_64"

# ====================
# 检查依赖
# ====================

if [ ! `which cmake` ]; then
    echo "❌ Error: cmake not found. Please install via 'brew install cmake'"
    exit 1
fi

if [ ! `which yasm` ] && [ ! `which nasm` ]; then
    echo "❌ Error: yasm or nasm not found. Please install via 'brew install yasm'"
    exit 1
fi

# ====================
# 下载源码
# ====================

if [ ! -r $SOURCE_DIR ]; then
    echo "⬇️  Downloading x265 $X265_VERSION..."
    curl -L $SOURCE_URL | tar xz || exit 1
    
    echo "🩹 Patching CMakeLists.txt for modern CMake..."
    # 移除旧的策略设置
    sed -i '' 's/cmake_policy(SET CMP0025 OLD)//g' "$SOURCE_DIR/source/CMakeLists.txt"
    sed -i '' 's/cmake_policy(SET CMP0054 OLD)//g' "$SOURCE_DIR/source/CMakeLists.txt"
    # 提高最小版本要求以避免警告
    sed -i '' 's/cmake_minimum_required(VERSION 2.8.8)/cmake_minimum_required(VERSION 3.5)/g' "$SOURCE_DIR/source/CMakeLists.txt"
else
    echo "✅ Source $SOURCE_DIR already exists."
fi

# ====================
# 编译循环
# ====================

CWD=`pwd`

for ARCH in $ARCHS
do
    echo "----------------------------------------"
    echo "🏗  Building x265 for $ARCH..."
    echo "----------------------------------------"

    mkdir -p "$SCRATCH/$ARCH"
    cd "$SCRATCH/$ARCH"

    # 配置架构相关参数
    if [ "$ARCH" = "arm64" ]; then
        PLATFORM="iPhoneOS"
        HOST="aarch64-apple-darwin"
        # x265 的 CMake 对 arm64 需要显式指定
        CMAKE_ARCH_ARGS="-DCMAKE_SYSTEM_PROCESSOR=aarch64"
    elif [ "$ARCH" = "x86_64" ]; then
        PLATFORM="iPhoneSimulator"
        HOST="x86_64-apple-darwin"
        CMAKE_ARCH_ARGS="-DCMAKE_SYSTEM_PROCESSOR=x86_64"
    else
        echo "Unsupported architecture: $ARCH"
        exit 1
    fi

    XCRUN_SDK=`echo $PLATFORM | tr '[:upper:]' '[:lower:]'`
    SYSROOT=`xcrun -sdk $XCRUN_SDK --show-sdk-path`
    
    # 编译标志
    CFLAGS="-arch $ARCH -isysroot $SYSROOT -miphoneos-version-min=$DEPLOYMENT_TARGET -fembed-bitcode -Wno-unused-command-line-argument"
    CXXFLAGS="$CFLAGS"

    # 执行 CMake
    # 注意：添加 -DENABLE_ASSEMBLY=OFF 以解决 iOS 上的链接符号缺失问题
    cmake "$CWD/$SOURCE_DIR/source" \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DCMAKE_POLICY_DEFAULT_CMP0025=NEW \
        -DCMAKE_POLICY_DEFAULT_CMP0054=NEW \
        -DCMAKE_SYSTEM_NAME=Darwin \
        -DCMAKE_SYSTEM_PROCESSOR=$ARCH \
        -DCMAKE_OSX_SYSROOT=$SYSROOT \
        -DCMAKE_C_COMPILER=$(xcrun -find clang) \
        -DCMAKE_CXX_COMPILER=$(xcrun -find clang++) \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
        -DENABLE_SHARED=OFF \
        -DENABLE_CLI=OFF \
        -DENABLE_ASSEMBLY=OFF \
        -DCMAKE_INSTALL_PREFIX="$THIN/$ARCH" \
        $CMAKE_ARCH_ARGS

    # 编译并安装
    make -j4 install || exit 1
    
    cd $CWD
done

# ====================
# 合并库 (Fat Binary)
# ====================

echo "----------------------------------------"
echo "📦 Creating Fat Library..."
echo "----------------------------------------"

if [ -d "$FAT" ]; then
    rm -rf "$FAT"
fi
mkdir -p "$FAT/lib"
mkdir -p "$FAT/include"

# 1. 合并 libx265.a
LIPO_ARGS=""
for ARCH in $ARCHS
    do
    LIPO_ARGS="$LIPO_ARGS $THIN/$ARCH/lib/libx265.a"
done

lipo -create $LIPO_ARGS -output "$FAT/lib/libx265.a" || exit 1

# 2. 拷贝头文件
# x265 会生成 x265_config.h，不同架构可能略有不同。
# 通常 arm64 是主架构，我们复制 arm64 的头文件作为通用头文件。
# 注意：如果 x265_config.h 中有架构特定的宏，混合使用可能会有警告，但在 iOS 场景下通常兼容。
cp -r $THIN/arm64/include/* "$FAT/include/"

echo "----------------------------------------"
echo "✅ Done! x265 library is in: $FAT"
echo "----------------------------------------"
