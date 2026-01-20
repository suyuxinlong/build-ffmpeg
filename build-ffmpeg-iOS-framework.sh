#!/bin/sh

set -e

# 配置
FRAMEWORK_NAME="FFmpeg"
FRAMEWORK_DIR="${FRAMEWORK_NAME}.framework"
BUILD_DIR="FFmpeg-iOS"
FFMPEG_VERSION="7.1" # 与 build-ffmpeg.sh 保持一致

# 1. 检查构建产物
if [ ! -d "$BUILD_DIR" ]; then
    echo "⚠️  $BUILD_DIR not found. Running build-ffmpeg.sh..."
    ./build-ffmpeg.sh "arm64 x86_64"
fi

if [ ! -d "$BUILD_DIR/lib" ] || [ ! -d "$BUILD_DIR/include" ]; then
    echo "❌ Error: Build artifacts in $BUILD_DIR are missing or incomplete."
    exit 1
fi

echo "🚀 Generating $FRAMEWORK_NAME.framework..."

# 2. 清理并创建目录
rm -rf "$FRAMEWORK_DIR"
mkdir -p "$FRAMEWORK_DIR/Headers"
mkdir -p "$FRAMEWORK_DIR/Modules"

# 3. 合并静态库 (Creating the fat binary)
echo "📦 Merging static libraries into one binary..."
# 使用 libtool 将所有 .a 文件合并为一个大的静态库文件
# 注意：这里假设 FFmpeg-iOS/lib 下的所有 .a 文件都是我们需要合并的
LIB_FILES=$(find "$BUILD_DIR/lib" -name "*.a")

# Include external libraries
if [ -d "fat-x264/lib" ]; then LIB_FILES="$LIB_FILES $(find fat-x264/lib -name "*.a")"; fi
if [ -d "fat-x265/lib" ]; then LIB_FILES="$LIB_FILES $(find fat-x265/lib -name "*.a")"; fi
if [ -d "fdk-aac-ios/lib" ]; then LIB_FILES="$LIB_FILES $(find fdk-aac-ios/lib -name "*.a")"; fi
if [ -d "fat-dav1d/lib" ]; then LIB_FILES="$LIB_FILES $(find fat-dav1d/lib -name "*.a")"; fi
if [ -d "fat-lame/lib" ]; then LIB_FILES="$LIB_FILES $(find fat-lame/lib -name "*.a")"; fi
if [ -d "fat-opus/lib" ]; then LIB_FILES="$LIB_FILES $(find fat-opus/lib -name "*.a")"; fi
if [ -d "fat-vpx/lib" ]; then LIB_FILES="$LIB_FILES $(find fat-vpx/lib -name "*.a")"; fi
if [ -d "fat-ogg/lib" ]; then LIB_FILES="$LIB_FILES $(find fat-ogg/lib -name "*.a")"; fi
if [ -d "fat-vorbis/lib" ]; then LIB_FILES="$LIB_FILES $(find fat-vorbis/lib -name "*.a")"; fi
if [ -d "fat-theora/lib" ]; then LIB_FILES="$LIB_FILES $(find fat-theora/lib -name "*.a")"; fi

libtool -static -o "$FRAMEWORK_DIR/$FRAMEWORK_NAME" $LIB_FILES

# 4. 拷贝头文件 (Headers)
echo "📄 Copying headers..."
# 直接拷贝 include 下的所有内容，保留目录结构 (如 libavcodec/avcodec.h)
# 这样在工程中设置 Header Search Paths 后，可以使用 #include <libavcodec/avcodec.h>
cp -R "$BUILD_DIR/include/" "$FRAMEWORK_DIR/Headers/"

# 5. 创建 Umbrella Header
echo "☔️ Creating umbrella header..."
UMBRELLA_HEADER="$FRAMEWORK_DIR/Headers/$FRAMEWORK_NAME.h"
cat > "$UMBRELLA_HEADER" <<EOF
#import <Foundation/Foundation.h>

//! Project version number for $FRAMEWORK_NAME.
FOUNDATION_EXPORT double ${FRAMEWORK_NAME}VersionNumber;

//! Project version string for $FRAMEWORK_NAME.
FOUNDATION_EXPORT const unsigned char ${FRAMEWORK_NAME}VersionString[];

// Import headers
// Users should add the framework Headers path to their Header Search Paths.
// Example: #include <libavcodec/avcodec.h>
EOF

# 6. 创建 Module Map (Swift Support)
echo "🗺  Creating module map..."
cat > "$FRAMEWORK_DIR/Modules/module.modulemap" <<EOF
framework module $FRAMEWORK_NAME {
    umbrella header "$FRAMEWORK_NAME.h"
    export *
    module * { export * }
}
EOF

# 7. 创建 Info.plist
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
    <string>$FFMPEG_VERSION</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>MinimumOSVersion</key>
    <string>12.0</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>iPhoneOS</string>
    </array>
</dict>
</plist>
EOF

echo "✅ $FRAMEWORK_NAME.framework created successfully!"
echo "   Location: $(pwd)/$FRAMEWORK_DIR"
echo "   (Make sure to add the 'Headers' directory to your project's 'Header Search Paths' if Xcode doesn't index subfolders automatically)"