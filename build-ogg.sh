#!/bin/sh

# ============================================================================
# 脚本用途：下载并编译适用于 iOS 的 libogg 静态库
# ============================================================================

OGG_VERSION="1.3.5"
SOURCE_URL="https://downloads.xiph.org/releases/ogg/libogg-$OGG_VERSION.tar.gz"
SOURCE_DIR="libogg-$OGG_VERSION"

FAT="fat-ogg"
SCRATCH="scratch-ogg"
THIN=`pwd`"/thin-ogg"

DEPLOYMENT_TARGET="12.0"
ARCHS="arm64 x86_64"

if [ ! -r $SOURCE_DIR ]; then
    echo "⬇️  Downloading libogg..."
    curl -L $SOURCE_URL | tar xz || exit 1
fi

CWD=`pwd`

for ARCH in $ARCHS
do
    echo "----------------------------------------"
    echo "🏗  Building libogg for $ARCH..."
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

    $CWD/$SOURCE_DIR/configure \
        --host=$HOST \
        --disable-shared \
        --enable-static \
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
    LIPO_ARGS="$LIPO_ARGS $THIN/$ARCH/lib/libogg.a"
done

lipo -create $LIPO_ARGS -output "$FAT/lib/libogg.a" || exit 1
cp -r $THIN/arm64/include/* "$FAT/include/"

echo "✅ Done! libogg library is in: $FAT"
