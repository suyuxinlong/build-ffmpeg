#!/bin/sh

# ============================================================================
# 脚本用途：下载并编译适用于 iOS 的 libtheora 静态库
# 依赖：需要先编译 libogg，且 fat-ogg 目录存在
# ============================================================================

THEORA_VERSION="1.1.1"
SOURCE_URL="https://downloads.xiph.org/releases/theora/libtheora-$THEORA_VERSION.tar.gz"
SOURCE_DIR="libtheora-$THEORA_VERSION"

FAT="fat-theora"
SCRATCH="scratch-theora"
THIN=`pwd`"/thin-theora"
OGG_DIR=`pwd`"/fat-ogg"

DEPLOYMENT_TARGET="12.0"
ARCHS="arm64 x86_64"

if [ ! -d "$OGG_DIR" ]; then
    echo "❌ Error: fat-ogg not found. Please run build-ogg.sh first."
    exit 1
fi

if [ ! -r $SOURCE_DIR ]; then
    echo "⬇️  Downloading libtheora..."
    curl -L $SOURCE_URL | tar xz || exit 1
fi

CWD=`pwd`

# libtheora 1.1.1 的 configure 需要 patching 才能支持最新的 config.guess/sub 或者接受 arm64
# 我们可能需要手动下载最新的 config.guess 和 config.sub 替换
if [ -d $SOURCE_DIR ]; then
    curl -L "http://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.guess;hb=HEAD" -o "$SOURCE_DIR/config.guess"
    curl -L "http://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.sub;hb=HEAD" -o "$SOURCE_DIR/config.sub"
    # Patch configure to remove obsolete linker flag
    sed -i '' 's/-force_cpusubtype_ALL//g' "$SOURCE_DIR/configure"
fi

for ARCH in $ARCHS
do
    echo "----------------------------------------"
    echo "🏗  Building libtheora for $ARCH..."
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

    OGG_CFLAGS="-I$OGG_DIR/include"
    OGG_LDFLAGS="-L$OGG_DIR/lib"

    # --disable-examples 避免编译示例程序，因为它们可能链接失败
    $CWD/$SOURCE_DIR/configure \
        --host=$HOST \
        --disable-shared \
        --enable-static \
        --disable-examples \
        --disable-sdltest \
        --disable-vorbistest \
        --disable-oggtest \
        --prefix="$THIN/$ARCH" \
        CC="$CC" \
        CFLAGS="$CFLAGS $OGG_CFLAGS" \
        LDFLAGS="$CFLAGS $OGG_LDFLAGS" || exit 1

    make -j4 install || exit 1
    cd $CWD
done

echo "----------------------------------------"
echo "📦 Creating Fat Library..."
echo "----------------------------------------"
mkdir -p "$FAT/lib"
mkdir -p "$FAT/include"

LIPO_ARGS=""
# libtheora 生成 libtheora.a, libtheoradec.a, libtheoraenc.a
LIBS="libtheora.a libtheoradec.a libtheoraenc.a"

for LIB in $LIBS
do
    LIPO_ARGS=""
    for ARCH in $ARCHS
    do
        LIPO_ARGS="$LIPO_ARGS $THIN/$ARCH/lib/$LIB"
    done
    lipo -create $LIPO_ARGS -output "$FAT/lib/$LIB" || exit 1
done

cp -r $THIN/arm64/include/* "$FAT/include/"

echo "✅ Done! libtheora library is in: $FAT"

