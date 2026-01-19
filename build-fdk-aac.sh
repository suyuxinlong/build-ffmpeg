#!/bin/sh

# ============================================================================
# 脚本用途：下载并编译适用于 iOS 的 fdk-aac 静态库
# 依赖工具：autoconf, automake, libtool
# ============================================================================

FDK_REPO="https://github.com/mstorsjo/fdk-aac.git"
FDK_VERSION="master"

FAT="fdk-aac-ios"
SCRATCH="scratch-fdk-aac"
THIN=`pwd`"/thin-fdk-aac"

DEPLOYMENT_TARGET="9.0"
ARCHS="arm64 x86_64"

# ====================
# 检查依赖
# ====================
if [ ! `which autoconf` ] || [ ! `which automake` ] || [ ! `which glibtool` ]; then
    echo "❌ Error: autotools not found. Please install via 'brew install autoconf automake libtool'"
    exit 1
fi

if [ ! -d "fdk-aac" ]; then
    echo "⬇️  Cloning fdk-aac..."
    git clone $FDK_REPO fdk-aac || exit 1
else
    echo "✅ fdk-aac source found."
fi

CWD=`pwd`

# 只有第一次 clone 后需要 autogen
if [ ! -f "fdk-aac/configure" ]; then
    echo "⚙️  Running autogen..."
    cd fdk-aac
    ./autogen.sh || exit 1
    cd $CWD
fi

# ====================
# 编译循环
# ====================
for ARCH in $ARCHS
do
    echo "----------------------------------------"
    echo "🏗  Building fdk-aac for $ARCH..."
    echo "----------------------------------------"

    mkdir -p "$SCRATCH/$ARCH"
    cd "$SCRATCH/$ARCH"

    if [ "$ARCH" = "arm64" ]; then
        PLATFORM="iPhoneOS"
        HOST="aarch64-apple-darwin"
    elif [ "$ARCH" = "x86_64" ]; then
        PLATFORM="iPhoneSimulator"
        HOST="x86_64-apple-darwin"
    fi

    XCRUN_SDK=`echo $PLATFORM | tr '[:upper:]' '[:lower:]'`
    SYSROOT=`xcrun -sdk $XCRUN_SDK --show-sdk-path`
    CC="xcrun -sdk $XCRUN_SDK clang"
    CXX="xcrun -sdk $XCRUN_SDK clang++"
    
    CFLAGS="-arch $ARCH -mios-version-min=$DEPLOYMENT_TARGET -fembed-bitcode -isysroot $SYSROOT"
    if [ "$ARCH" = "x86_64" ]; then
        CFLAGS="-arch $ARCH -mios-simulator-version-min=$DEPLOYMENT_TARGET -fembed-bitcode -isysroot $SYSROOT"
    fi

    # fdk-aac 使用标准 autotools 流程
    $CWD/fdk-aac/configure \
        --host=$HOST \
        --enable-static \
        --disable-shared \
        --prefix="$THIN/$ARCH" \
        CC="$CC" \
        CXX="$CXX" \
        CFLAGS="$CFLAGS" \
        CXXFLAGS="$CFLAGS" \
        LDFLAGS="$CFLAGS" || exit 1

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
    LIPO_ARGS="$LIPO_ARGS $THIN/$ARCH/lib/libfdk-aac.a"
done

lipo -create $LIPO_ARGS -output "$FAT/lib/libfdk-aac.a" || exit 1
cp -r $THIN/arm64/include/* "$FAT/include/"

echo "✅ Done! fdk-aac library is in: $FAT"
