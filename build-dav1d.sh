#!/bin/sh

# ============================================================================
# 脚本用途：下载并编译适用于 iOS 的 dav1d (AV1) 静态库
# 依赖工具：meson, ninja
# ============================================================================

DAV1D_REPO="https://code.videolan.org/videolan/dav1d.git"
DAV1D_VERSION="master"

FAT="fat-dav1d"
THIN=`pwd`"/thin-dav1d"

DEPLOYMENT_TARGET="9.0"
ARCHS="arm64 x86_64"

# ====================
# 检查依赖
# ====================
if [ ! `which meson` ] || [ ! `which ninja` ]; then
    echo "❌ Error: meson or ninja not found. Please install via 'brew install meson ninja'"
    exit 1
fi

if [ ! -d "dav1d" ]; then
    echo "⬇️  Cloning dav1d..."
    git clone $DAV1D_REPO dav1d || exit 1
else
    echo "✅ dav1d source found."
fi

CWD=`pwd`

# ====================
# 辅助函数: 生成 Meson Cross File
# ====================
create_cross_file() {
    local ARCH=$1
    local CROSS_FILE=$2
    local SYSROOT=$3
    local MIN_VER_FLAG=$4

    # 确定 cpu_family
    if [ "$ARCH" = "arm64" ]; then
        CPU_FAM="aarch64"
        CPU="aarch64"
    elif [ "$ARCH" = "x86_64" ]; then
        CPU_FAM="x86_64"
        CPU="x86_64"
    fi

    cat > $CROSS_FILE <<EOF
[binaries]
c = 'clang'
cpp = 'clang++'
ar = 'ar'
strip = 'strip'
pkgconfig = 'pkg-config'

[built-in options]
c_args = ['-arch', '$ARCH', '$MIN_VER_FLAG=$DEPLOYMENT_TARGET', '-isysroot', '$SYSROOT', '-fembed-bitcode']
cpp_args = ['-arch', '$ARCH', '$MIN_VER_FLAG=$DEPLOYMENT_TARGET', '-isysroot', '$SYSROOT', '-fembed-bitcode']
c_link_args = ['-arch', '$ARCH', '$MIN_VER_FLAG=$DEPLOYMENT_TARGET', '-isysroot', '$SYSROOT', '-fembed-bitcode']
cpp_link_args = ['-arch', '$ARCH', '$MIN_VER_FLAG=$DEPLOYMENT_TARGET', '-isysroot', '$SYSROOT', '-fembed-bitcode']

[host_machine]
system = 'darwin'
cpu_family = '$CPU_FAM'
cpu = '$CPU'
endian = 'little'
EOF
}

# ====================
# 编译循环
# ====================
for ARCH in $ARCHS
do
    echo "----------------------------------------"
    echo "🏗  Building dav1d for $ARCH..."
    echo "----------------------------------------"

    BUILD_DIR="dav1d/build-$ARCH"
    
    if [ "$ARCH" = "arm64" ]; then
        PLATFORM="iPhoneOS"
        MIN_VER_FLAG="-mios-version-min"
    elif [ "$ARCH" = "x86_64" ]; then
        PLATFORM="iPhoneSimulator"
        MIN_VER_FLAG="-mios-simulator-version-min"
    fi

    XCRUN_SDK=`echo $PLATFORM | tr '[:upper:]' '[:lower:]'`
    SYSROOT=`xcrun -sdk $XCRUN_SDK --show-sdk-path`
    
    # 生成交叉编译文件
    CROSS_FILE="$CWD/dav1d-cross-$ARCH.txt"
    create_cross_file "$ARCH" "$CROSS_FILE" "$SYSROOT" "$MIN_VER_FLAG"

    # Meson 配置
    # 如果构建目录已存在，先清理 (或者使用 --reconfigure，但清理更安全)
    rm -rf $BUILD_DIR
    
    meson setup $BUILD_DIR dav1d \
        --cross-file $CROSS_FILE \
        --buildtype release \
        --default-library static \
        --prefix "$THIN/$ARCH" || exit 1

    # 编译并安装
    ninja -C $BUILD_DIR install || exit 1
    
    # 清理临时 cross file
    rm $CROSS_FILE
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
    LIPO_ARGS="$LIPO_ARGS $THIN/$ARCH/lib/libdav1d.a"
done

lipo -create $LIPO_ARGS -output "$FAT/lib/libdav1d.a" || exit 1
cp -r $THIN/arm64/include/* "$FAT/include/"

echo "✅ Done! dav1d library is in: $FAT"
