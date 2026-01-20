#!/bin/bash

# 定义要清理的文件和目录模式
ITEMS_TO_CLEAN=(
    "ffmpeg-[0-9.]*"
    "FFmpeg-iOS"
    "FFmpeg-tvOS"
    "FFmpeg-Android"
    "FFmpeg*.framework"
    "dav1d"
    "fat-dav1d"
    "fdk-aac"
    "fdk-aac-ios"
    "fat-fdk-aac"
    "x264"
    "fat-x264"
    "x265-[0-9.]*"
    "fat-x265"
    "lame-[0-9.]*"
    "fat-lame"
    "libogg-[0-9.]*"
    "fat-ogg"
    "opus-[0-9.]*"
    "fat-opus"
    "libtheora-[0-9.]*"
    "fat-theora"
    "libvorbis-[0-9.]*"
    "fat-vorbis"
    "libvpx"
    "fat-vpx"
    "pkgconfig_temp"
    "scratch"
    "thin"
    "scratch-*"
    "thin-*"
    "tools_bin"
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
    # 使用 for 循环配合 find，避免 pipe 子进程导致数组变量无法传递的问题
    # 注意：如果文件名包含空格，这种写法会有问题，但在本项目环境下是安全的
    for item in $(find . -maxdepth 1 -name "$pattern" 2>/dev/null); do
        if [ -e "$item" ]; then
            clean_item="${item#./}"
            echo "  - $clean_item"
            FOUND_ITEMS+=("$clean_item")
        fi
    done
done

# 移除重复项并排序
if [ ${#FOUND_ITEMS[@]} -gt 0 ]; then
    # 使用临时文件或此处这种方式进行排序去重
    IFS=$'\n' sorted_items=($(printf "%s\n" "${FOUND_ITEMS[@]}" | sort -u))
    unset IFS
    FOUND_ITEMS=("${sorted_items[@]}")
fi

if [ ${#FOUND_ITEMS[@]} -eq 0 ]; then
    echo "  (No generated files found to clean)"
    echo "========================================"
    echo "Nothing to do."
    exit 0
fi

echo ""
echo "========================================"
# 使用更通用的 read 方式
printf "Are you sure you want to delete these ${#FOUND_ITEMS[@]} items? (y/N): "
read REPLY
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