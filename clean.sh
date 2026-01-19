#!/bin/bash

# 定义要清理的文件和目录模式
ITEMS_TO_CLEAN=(
    "ffmpeg-[0-9.]*"
    "FFmpeg-iOS"
    "FFmpeg-tvOS"
    "FFmpeg-tvOS.framework"
    "FFmpeg.framework"
    "dav1d"
    "fat-dav1d"
    "thin-dav1d"
    "scratch-dav1d"
    "fdk-aac"
    "fdk-aac-ios"
    "fat-fdk-aac"
    "thin-fdk-aac"
    "scratch-fdk-aac"
    "x264"
    "fat-x264"
    "thin-x264"
    "scratch-x264"
    "x265-[0-9.]*"
    "fat-x265"
    "thin-x265"
    "scratch-x265"
    "lame-[0-9.]*"
    "fat-lame"
    "thin-lame"
    "scratch-lame"
    "libogg-[0-9.]*"
    "fat-ogg"
    "thin-ogg"
    "scratch-ogg"
    "opus-[0-9.]*"
    "fat-opus"
    "thin-opus"
    "scratch-opus"
    "libtheora-[0-9.]*"
    "fat-theora"
    "thin-theora"
    "scratch-theora"
    "libvorbis-[0-9.]*"
    "fat-vorbis"
    "thin-vorbis"
    "scratch-vorbis"
    "libvpx"
    "fat-vpx"
    "thin-vpx"
    "scratch-vpx"
    "pkgconfig_temp"
    "scratch"
    "thin"
    "tools_bin"
    "scratch-tvos"
    "thin-tvos"
    "test_src"
    "test_dest"
    "dav1d-cross-*.txt"
)

echo "========================================"
echo "      FFmpeg Build Clean Script"
echo "========================================"
echo "The following files and directories will be REMOVED:"
echo ""

FOUND_ITEMS=()

# 查找并列出存在的项目
for pattern in "${ITEMS_TO_CLEAN[@]}"; do
    # 使用 find 查找匹配的项目，避免 glob 不匹配时的错误
    for item in $(find . -maxdepth 1 -name "$pattern" 2>/dev/null); do
        # 移除前面的 ./
        clean_item="${item#./}"
        echo "  - $clean_item"
        FOUND_ITEMS+=("$clean_item")
    done
done

if [ ${#FOUND_ITEMS[@]} -eq 0 ]; then
    echo "  (No generated files found to clean)"
    echo "========================================"
    echo "Nothing to do."
    exit 0
fi

echo ""
echo "========================================"
read -p "Are you sure you want to delete these ${#FOUND_ITEMS[@]} items? (y/N): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleaning..."
    for item in "${FOUND_ITEMS[@]}"; do
        rm -rf "$item"
        echo "  Deleted: $item"
    done
    echo "Done."
else
    echo "Operation cancelled."
fi
