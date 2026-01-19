#!/bin/sh

# ============================================================================
# 脚本用途：下载并编译适用于 iOS 的 libvorbis 静态库
# 依赖：需要先编译 libogg，且 fat-ogg 目录存在
# ============================================================================

VORBIS_VERSION="1.3.7"
SOURCE_URL="https://downloads.xiph.org/releases/vorbis/libvorbis-$VORBIS_VERSION.tar.gz"
SOURCE_DIR="libvorbis-$VORBIS_VERSION"

FAT="fat-vorbis"
SCRATCH="scratch-vorbis"
THIN=`pwd`"/thin-vorbis"
OGG_DIR=`pwd`"/fat-ogg"

DEPLOYMENT_TARGET="12.0"
ARCHS="arm64 x86_64"

if [ ! -d "$OGG_DIR" ]; then
    echo "❌ Error: fat-ogg not found. Please run build-ogg.sh first."
    exit 1
fi

if [ ! -r $SOURCE_DIR ]; then
    echo "⬇️  Downloading libvorbis..."
    curl -L $SOURCE_URL | tar xz || exit 1
fi

# Patch configure to remove obsolete linker flag that breaks on modern iOS SDKs
if [ -f "$SOURCE_DIR/configure" ]; then
    sed -i '' 's/-force_cpusubtype_ALL//g' "$SOURCE_DIR/configure"
fi

CWD=`pwd`

for ARCH in $ARCHS
do
    echo "----------------------------------------"
    echo "🏗  Building libvorbis for $ARCH..."
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

    # Vorbis 需要链接 Ogg，这里我们指向 fat-ogg (虽然不是单架构，但头文件通用，链接库时可能需要注意)
    # 最稳妥的是指向 thin/ARCH 下的 ogg，但为了简化，我们假设 fat-ogg 存在。
    # 实际上 configure 阶段主要检查头文件和库存在。
    # 我们这里显式指定 CFLAGS 和 LDFLAGS 包含 Ogg 路径
    
    OGG_CFLAGS="-I$OGG_DIR/include"
    OGG_LDFLAGS="-L$OGG_DIR/lib"

    $CWD/$SOURCE_DIR/configure \
        --host=$HOST \
        --disable-shared \
        --enable-static \
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
# libvorbis 会生成 libvorbis.a, libvorbisenc.a, libvorbisfile.a
LIBS="libvorbis.a libvorbisenc.a libvorbisfile.a"

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

echo "✅ Done! libvorbis library is in: $FAT"
