#!/bin/sh

# ============================================================================
# 脚本用途：下载并编译适用于 iOS 的 libvpx (VP8/VP9) 静态库
# ============================================================================

VPX_REPO="https://chromium.googlesource.com/webm/libvpx"
SOURCE_DIR="libvpx"

FAT="fat-vpx"
SCRATCH="scratch-vpx"
THIN=`pwd`"/thin-vpx"

DEPLOYMENT_TARGET="12.0"
ARCHS="arm64 x86_64"

if [ ! -d $SOURCE_DIR ]; then
    echo "⬇️  Cloning libvpx..."
    git clone $VPX_REPO $SOURCE_DIR || exit 1
else
    echo "✅ libvpx source found."
fi

CWD=`pwd`

for ARCH in $ARCHS
do
    echo "----------------------------------------"
    echo "🏗  Building libvpx for $ARCH..."
    echo "----------------------------------------"

    mkdir -p "$SCRATCH/$ARCH"
    cd "$SCRATCH/$ARCH"

    if [ "$ARCH" = "arm64" ]; then
        PLATFORM="iPhoneOS"
        TARGET="arm64-darwin20-gcc" # libvpx 使用特殊的 target 命名
    elif [ "$ARCH" = "x86_64" ]; then
        PLATFORM="iPhoneSimulator"
        TARGET="x86_64-darwin20-gcc"
    fi

    XCRUN_SDK=`echo $PLATFORM | tr '[:upper:]' '[:lower:]'`
    SYSROOT=`xcrun -sdk $XCRUN_SDK --show-sdk-path`
    CC="xcrun -sdk $XCRUN_SDK clang"
    CXX="xcrun -sdk $XCRUN_SDK clang++"
    
    # libvpx 需要通过 extra-cflags 传递 iOS 版本和 bitcode
    CFLAGS="-arch $ARCH -mios-version-min=$DEPLOYMENT_TARGET -fembed-bitcode -isysroot $SYSROOT"
    if [ "$ARCH" = "x86_64" ]; then
        CFLAGS="-arch $ARCH -mios-simulator-version-min=$DEPLOYMENT_TARGET -fembed-bitcode -isysroot $SYSROOT"
    fi

    # libvpx 的 configure 不支持 out-of-tree 构建太好，建议用 absolute path
    # 也可以直接调用 configure
    
    LDFLAGS="$CFLAGS" CC="$CC" CXX="$CXX" $CWD/$SOURCE_DIR/configure \
        --target=$TARGET \
        --disable-shared \
        --enable-static \
        --disable-examples \
        --disable-unit-tests \
        --disable-tools \
        --disable-docs \
        --enable-vp9-highbitdepth \
        --prefix="$THIN/$ARCH" \
        --extra-cflags="$CFLAGS" \
        --extra-cxxflags="$CFLAGS" || exit 1

    # 需要修改 Makefile 以确保使用正确的编译器 (libvpx configure 有时会忽略 CC 环境变量)
    # 但通常指定 --target 后它会自动查找 gcc/clang。但在 macOS 上，arm64-darwin-gcc 可能映射不到 xcrun
    # 所以我们可能需要手动干预一下 config.mk 或者依赖 configure 的智能检测
    # 观察：libvpx 的 configure 如果检测到 darwin，默认用 clang。
    
    # 强制覆盖 CC/CXX
    make -j4 install HAVE_GNU_STRIP=no CC="$CC" CXX="$CXX" || exit 1
    cd $CWD
done

echo "----------------------------------------"
echo "📦 Creating Fat Library..."
echo "----------------------------------------"
mkdir -p "$FAT/lib"
mkdir -p "$FAT/include"

LIPO_ARGS=""
for ARCH in $ARCHS
# The following line has been corrected from "$LIPO_ARGS" $THIN/$ARCH/lib/libvpx.a" to "$LIPO_ARGS $THIN/$ARCH/lib/libvpx.a"
do
    LIPO_ARGS="$LIPO_ARGS $THIN/$ARCH/lib/libvpx.a"
done

lipo -create $LIPO_ARGS -output "$FAT/lib/libvpx.a" || exit 1
cp -r $THIN/arm64/include/* "$FAT/include/"

echo "✅ Done! libvpx library is in: $FAT"
