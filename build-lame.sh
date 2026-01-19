#!/bin/sh

# ============================================================================
# 脚本用途：下载并编译适用于 iOS 的 libmp3lame 静态库
# ============================================================================

LAME_VERSION="3.100"
SOURCE_URL="https://downloads.sourceforge.net/project/lame/lame/$LAME_VERSION/lame-$LAME_VERSION.tar.gz"
SOURCE_DIR="lame-$LAME_VERSION"

FAT="fat-lame"
SCRATCH="scratch-lame"
THIN=`pwd`"/thin-lame"

DEPLOYMENT_TARGET="12.0"
ARCHS="arm64 x86_64"

if [ ! -r $SOURCE_DIR ]; then
    echo "⬇️  Downloading LAME..."
    curl -L $SOURCE_URL | tar xz || exit 1
fi

CWD=`pwd`

for ARCH in $ARCHS
do
    echo "----------------------------------------"
    echo "🏗  Building LAME for $ARCH..."
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
    
    CFLAGS="-arch $ARCH -mios-version-min=$DEPLOYMENT_TARGET -fembed-bitcode -isysroot $SYSROOT"
    if [ "$ARCH" = "x86_64" ]; then
        CFLAGS="-arch $ARCH -mios-simulator-version-min=$DEPLOYMENT_TARGET -fembed-bitcode -isysroot $SYSROOT"
    fi

    # LAME 的 configure 比较老旧，有时需要显式指定 AS
    # 并且 LAME 3.100 在并发 make 时可能有问题，建议 -j1
    $CWD/$SOURCE_DIR/configure \
        --host=$HOST \
        --disable-shared \
        --enable-static \
        --disable-frontend \
        --prefix="$THIN/$ARCH" \
        CC="$CC" \
        CFLAGS="$CFLAGS" \
        LDFLAGS="$CFLAGS" || exit 1

    make -j4 install || exit 1
    cd $CWD
done

echo "----------------------------------------"
echo "📦 Creating Fat Library..."
echo "----------------------------------------"
mkdir -p "$FAT/lib"
mkdir -p "$FAT/include"

LIPO_ARGS=""
for ARCH in $ARCHS
do
    LIPO_ARGS="$LIPO_ARGS $THIN/$ARCH/lib/libmp3lame.a"
done

lipo -create $LIPO_ARGS -output "$FAT/lib/libmp3lame.a" || exit 1
cp -r $THIN/arm64/include/* "$FAT/include/"

echo "✅ Done! libmp3lame library is in: $FAT"
