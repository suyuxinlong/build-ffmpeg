#!/bin/sh

set -e

# ====================
# 配置部分
# ====================
FF_VERSION="7.1"
SOURCE="ffmpeg-$FF_VERSION"
ARCHS="arm64 x86_64"
DEPLOYMENT_TARGET="12.0" # tvOS 最低版本
FRAMEWORK_NAME="FFmpeg"
FRAMEWORK_DIR="FFmpeg-tvOS.framework"
THIN_DIR=`pwd`/"thin-tvos"
SCRATCH_DIR="scratch-tvos"

# 必须禁用某些在 tvOS 上不可用的模块
CONFIGURE_FLAGS="--enable-cross-compile --disable-debug --disable-programs \
                 --disable-doc --enable-pic \
                 --disable-audiotoolbox \
                 --disable-indev=avfoundation --disable-outdev=audiotoolbox \
                 --disable-swscale-alpha --disable-decoder=vvc --disable-parser=vvc"

# ====================
# 1. 环境准备
# ====================

# 确保本地工具链可用 (复用 build-ffmpeg.sh 的工具)
export PATH=`pwd`/tools_bin:$PATH

if [ ! `which yasm` ]; then
    echo "⚠️  Yasm not found. Installing..."
    brew install yasm || exit 1
fi

if [ ! `which gas-preprocessor.pl` ]; then
    echo "⚠️  gas-preprocessor.pl not found. Installing locally..."
    mkdir -p tools_bin
    curl -L https://github.com/libav/gas-preprocessor/raw/master/gas-preprocessor.pl \
        -o tools_bin/gas-preprocessor.pl \
        && chmod +x tools_bin/gas-preprocessor.pl || exit 1
fi

# 下载源码
if [ ! -r $SOURCE ]; then
    echo "⬇️  Downloading FFmpeg $FF_VERSION..."
    curl -L http://www.ffmpeg.org/releases/$SOURCE.tar.bz2 | tar xj || exit 1
fi

CWD=`pwd`

# ====================
# 2. 编译流程
# ====================

for ARCH in $ARCHS
do
    echo "----------------------------------------"
    echo "🏗  Building FFmpeg (tvOS) for $ARCH..."
    echo "----------------------------------------"
    
    mkdir -p "$SCRATCH_DIR/$ARCH"
    cd "$SCRATCH_DIR/$ARCH"

    CFLAGS="-arch $ARCH"
    EXPORT=""
    
    if [ "$ARCH" = "x86_64" ]; then
        PLATFORM="AppleTVSimulator"
        CFLAGS="$CFLAGS -mtvos-simulator-version-min=$DEPLOYMENT_TARGET"
    else
        PLATFORM="AppleTVOS"
        CFLAGS="$CFLAGS -mtvos-version-min=$DEPLOYMENT_TARGET -fembed-bitcode"
        if [ "$ARCH" = "arm64" ]; then EXPORT="GASPP_FIX_XCODE5=1"; fi
    fi

    XCRUN_SDK=`echo $PLATFORM | tr '[:upper:]' '[:lower:]'`
    CC="xcrun -sdk $XCRUN_SDK clang"
    
    # gas-preprocessor 处理汇编
    if [ "$ARCH" = "arm64" ]; then
        AS="gas-preprocessor.pl -arch aarch64 -- $CC"
    else
        AS="gas-preprocessor.pl -- $CC"
    fi

    TMPDIR=${TMPDIR/%emoveChild/} $CWD/$SOURCE/configure \
        --target-os=darwin \
        --arch=$ARCH \
        --cc="$CC" \
        --as="$AS" \
        $CONFIGURE_FLAGS \
        --extra-cflags="$CFLAGS" \
        --extra-ldflags="$CFLAGS" \
        --prefix="$THIN_DIR/$ARCH" || exit 1

    make -j4 install $EXPORT || exit 1
    cd $CWD
done

# ====================
# 3. 生成 Framework
# ====================

echo "----------------------------------------"
echo "🚀 Generating $FRAMEWORK_DIR..."
echo "----------------------------------------"

# 清理旧文件
rm -rf "$FRAMEWORK_DIR"
mkdir -p "$FRAMEWORK_DIR/Headers"
mkdir -p "$FRAMEWORK_DIR/Modules"

# 合并静态库 (arm64 + x86_64)
echo "📦 Merging libraries..."
mkdir -p "$SCRATCH_DIR/fat_libs"
LIBS_TO_MERGE=""

# 获取第一个架构下的库列表作为基准
FIRST_ARCH=$(echo $ARCHS | awk '{print $1}')
cd "$THIN_DIR/$FIRST_ARCH/lib"
LIB_NAMES=$(ls *.a)
cd $CWD

for LIB in $LIB_NAMES; do
    echo "   Processing $LIB..."
    LIPO_ARGS=""
    for ARCH in $ARCHS;
    do
        LIPO_ARGS="$LIPO_ARGS $THIN_DIR/$ARCH/lib/$LIB"
    done
    lipo -create $LIPO_ARGS -output "$SCRATCH_DIR/fat_libs/$LIB"
    LIBS_TO_MERGE="$LIBS_TO_MERGE $SCRATCH_DIR/fat_libs/$LIB"
done

# 最终合并为一个 Framework 二进制
libtool -static -o "$FRAMEWORK_DIR/$FRAMEWORK_NAME" $LIBS_TO_MERGE

# 拷贝头文件 (使用第一个架构的头文件即可，通常是一样的)
echo "📄 Copying headers..."
cp -R "$THIN_DIR/$FIRST_ARCH/include/" "$FRAMEWORK_DIR/Headers/"

# 创建 Umbrella Header
echo "☔️ Creating umbrella header..."
UMBRELLA_HEADER="$FRAMEWORK_DIR/$FRAMEWORK_NAME.h"
cat > "$UMBRELLA_HEADER" <<EOF
#import <Foundation/Foundation.h>

//! Project version number for $FRAMEWORK_NAME.
FOUNDATION_EXPORT double ${FRAMEWORK_NAME}VersionNumber;

//! Project version string for $FRAMEWORK_NAME.
FOUNDATION_EXPORT const unsigned char ${FRAMEWORK_NAME}VersionString[];

// Import headers
// Example: #include <libavcodec/avcodec.h>
EOF

# 创建 Module Map
echo "🗺  Creating module map..."
cat > "$FRAMEWORK_DIR/Modules/module.modulemap" <<EOF
framework module $FRAMEWORK_NAME {
    umbrella header "$FRAMEWORK_NAME.h"
    export *
    module * { export * }
}
EOF

# 创建 Info.plist
echo "📝 Creating Info.plist..."
cat > "$FRAMEWORK_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$FRAMEWORK_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>org.ffmpeg.$FRAMEWORK_NAME</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$FRAMEWORK_NAME</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>$FF_VERSION</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>MinimumOSVersion</key>
    <string>$DEPLOYMENT_TARGET</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>AppleTVOS</string>
    </array>
    <key>UIDeviceFamily</key>
    <array>
        <integer>3</integer>
    </array>
</dict>
</plist>
EOF

echo "✅ $FRAMEWORK_DIR created successfully!"
echo "   Location: $(pwd)/$FRAMEWORK_DIR"