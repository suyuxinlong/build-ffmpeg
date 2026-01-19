#!/bin/sh

# ============================================================================
# 脚本用途：下载并编译适用于 iOS 的 FFmpeg 静态库
# 功能特点：
#   1. 自动下载 FFmpeg 源码 (留空 FF_VERSION 自动获取最新版)
#   2. 支持多架构编译 (arm64, x86_64 等)
#   3. 智能检测并集成第三方库 (x264, x265, fdk-aac, dav1d)
#   4. 自动合并生成 Fat 库 (使用 lipo)
# ============================================================================

# ====================
# 版本与目录配置
# ====================

# FFmpeg 版本号 (强制指定 7.1 以获得最佳兼容性)
FF_VERSION="7.1"
if [[ $FFMPEG_VERSION != "" ]]; then
  FF_VERSION=$FFMPEG_VERSION
fi

echo "使用 FFmpeg 版本: $FF_VERSION"

SOURCE="ffmpeg-$FF_VERSION"
FAT="FFmpeg-iOS"
SCRATCH="scratch"
THIN=`pwd`"/thin"

# ====================
# 第三方库路径配置 (自动检测)
# ====================

detect_lib_path() {
    local LIB_NAME=$1
    local VAR_REF=$2
    local POSSIBLE_DIRS=$3
    eval CURRENT_VAL=\$$VAR_REF
    if [ -n "$CURRENT_VAL" ]; then
        echo "ℹ️  [$LIB_NAME] 使用手动配置路径: $CURRENT_VAL"
        return
    fi
    for SEARCH_BASE in "." ".."; do
        for DIR_NAME in $POSSIBLE_DIRS; do
            local CANDIDATE_PATH="$SEARCH_BASE/$DIR_NAME"
            if [ -d "$CANDIDATE_PATH" ] && [ -d "$CANDIDATE_PATH/include" ] && [ -d "$CANDIDATE_PATH/lib" ]; then
                local ABS_PATH=$(cd "$CANDIDATE_PATH" && pwd)
                eval $VAR_REF="'$ABS_PATH'"
                echo "✅ 成功检测到 $LIB_NAME: $ABS_PATH"
                return
            fi
        done
    done
    echo "⚠️  未找到 $LIB_NAME，将跳过集成。"
}

detect_lib_path "x264"    "X264"    "fat-x264 x264-ios x264"
detect_lib_path "x265"    "X265"    "fat-x265 x265-ios x265"
detect_lib_path "fdk-aac" "FDK_AAC" "fdk-aac-ios fdk-aac fat-fdk-aac"
detect_lib_path "dav1d"   "DAV1D"   "fat-dav1d dav1d-ios dav1d"
detect_lib_path "lame"    "LAME"    "fat-lame lame-ios lame"
detect_lib_path "opus"    "OPUS"    "fat-opus opus-ios opus"
detect_lib_path "vpx"     "VPX"     "fat-vpx vpx-ios vpx"
detect_lib_path "ogg"     "OGG"     "fat-ogg ogg-ios ogg"
detect_lib_path "vorbis"  "VORBIS"  "fat-vorbis vorbis-ios vorbis"
detect_lib_path "theora"  "THEORA"  "fat-theora theora-ios theora"

# ====================
# Configure 基础选项
# ====================

CONFIGURE_FLAGS="--enable-cross-compile --disable-debug --disable-programs \
                 --disable-doc --enable-pic --disable-audiotoolbox --disable-indev=avfoundation --disable-outdev=audiotoolbox \
                 --disable-decoder=vvc --disable-parser=vvc"

if [ "$X264" ]; then
    CONFIGURE_FLAGS="$CONFIGURE_FLAGS --enable-gpl --enable-libx264"
fi

if [ "$X265" ]; then
    CONFIGURE_FLAGS="$CONFIGURE_FLAGS --enable-gpl --enable-libx265"
fi

if [ "$FDK_AAC" ]; then
    CONFIGURE_FLAGS="$CONFIGURE_FLAGS --enable-libfdk-aac --enable-nonfree"
fi

if [ "$DAV1D" ]; then
    CONFIGURE_FLAGS="$CONFIGURE_FLAGS --enable-libdav1d"
fi

if [ "$LAME" ]; then
    CONFIGURE_FLAGS="$CONFIGURE_FLAGS --enable-libmp3lame"
fi

if [ "$OPUS" ]; then
    CONFIGURE_FLAGS="$CONFIGURE_FLAGS --enable-libopus"
fi

if [ "$VPX" ]; then
    CONFIGURE_FLAGS="$CONFIGURE_FLAGS --enable-libvpx"
fi

if [ "$VORBIS" ]; then
    CONFIGURE_FLAGS="$CONFIGURE_FLAGS --enable-libvorbis"
fi

if [ "$THEORA" ]; then
    CONFIGURE_FLAGS="$CONFIGURE_FLAGS --enable-libtheora"
fi

# ====================
# 架构与构建控制
# ====================

ARCHS="arm64 x86_64"
COMPILE="y"
LIPO="y"
DEPLOYMENT_TARGET="12.0"

if [ "$*" ]; then
    if [ "$*" = "lipo" ]; then
        COMPILE=
    else
        ARCHS="$*"
    fi
fi

# ====================
# 编译流程
# ====================

if [ "$COMPILE" ]; then
    # 检查依赖
    if [ ! `which yasm` ]; then
        echo 'Trying to install Yasm...'
        brew install yasm || exit 1
    fi
    
    # 本地工具路径 (包含劫持版 pkg-config)
    mkdir -p tools_bin
    export PATH=`pwd`/tools_bin:$PATH
    
    # 创建“劫持版” pkg-config
    cat > tools_bin/pkg-config <<EOF
#!/bin/bash
pkg=\$1
case "\$*" in
    *--exists*)
        exit 0
        ;;
    *--cflags*)
        case "\$*" in
            *x264*)    echo "-I$X264/include" ;;
            *x265*)    echo "-I$X265/include" ;;
            *fdk-aac*) echo "-I$FDK_AAC/include" ;;
            *dav1d*)   echo "-I$DAV1D/include" ;;
            *lame*)    echo "-I$LAME/include" ;;
            *opus*)    echo "-I$OPUS/include/opus" ;;
            *vpx*)     echo "-I$VPX/include" ;;
            *ogg*)     echo "-I$OGG/include" ;;
            *vorbis*)  echo "-I$VORBIS/include" ;;
            *theora*)  echo "-I$THEORA/include" ;;
        esac
        exit 0
        ;;
    *--libs*)
        case "\$*" in
            *x264*)    echo "-L$X264/lib -lx264" ;;
            *x265*)    echo "-L$X265/lib -lx265 -lc++" ;;
            *fdk-aac*) echo "-L$FDK_AAC/lib -lfdk-aac" ;;
            *dav1d*)   echo "-L$DAV1D/lib -ldav1d" ;;
            *lame*)    echo "-L$LAME/lib -lmp3lame" ;;
            *opus*)    echo "-L$OPUS/lib -lopus" ;;
            *vpx*)     echo "-L$VPX/lib -lvpx" ;;
            *ogg*)     echo "-L$OGG/lib -logg" ;;
            *vorbis*)  echo "-L$VORBIS/lib -lvorbis -lvorbisenc -lvorbisfile -L$OGG/lib -logg" ;;
            *theora*)  echo "-L$THEORA/lib -ltheora -ltheoradec -ltheoraenc -L$OGG/lib -logg" ;;
        esac
        exit 0
        ;;
esac
# 对于其他库，尝试调用系统的 pkg-config (如果存在)
if [ -x /opt/homebrew/bin/pkg-config ]; then
    /opt/homebrew/bin/pkg-config "\$@"
else
    /usr/bin/pkg-config "\$@" 2>/dev/null || exit 0
fi
EOF
    chmod +x tools_bin/pkg-config

    if [ ! `which gas-preprocessor.pl` ]; then
        echo 'Installing gas-preprocessor.pl locally...'
        curl -L https://github.com/libav/gas-preprocessor/raw/master/gas-preprocessor.pl \
            -o tools_bin/gas-preprocessor.pl \
            && chmod +x tools_bin/gas-preprocessor.pl || exit 1
    fi

    # 下载源码
    if [ ! -r $SOURCE ]; then
        echo "Downloading $SOURCE..."
        curl -L http://www.ffmpeg.org/releases/$SOURCE.tar.bz2 | tar xj || exit 1
    fi

    CWD=`pwd`
    # 创建临时 PC 文件存放目录
    mkdir -p "$CWD/pkgconfig_temp"
    export PKG_CONFIG_PATH="$CWD/pkgconfig_temp:$PKG_CONFIG_PATH"

    for ARCH in $ARCHS
    do
        echo "🏗  Building $ARCH..."
        
        # 为当前架构动态生成 PC 文件，确保路径正确
        if [ "$X264" ]; then
            cat > "$CWD/pkgconfig_temp/x264.pc" <<EOF
prefix=$X264
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include
Name: x264
Description: H.264 (MPEG4 AVC) encoder library
Version: 0.164.x
Libs: -L\${libdir} -lx264
Cflags: -I\${includedir}
EOF
        fi
        if [ "$X265" ]; then
            cat > "$CWD/pkgconfig_temp/x265.pc" <<EOF
prefix=$X265
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include
Name: x265
Description: H.265 (HEVC) encoder library
Version: 3.4
Libs: -L\${libdir} -lx265 -lc++
Cflags: -I\${includedir}
EOF
        fi
        if [ "$FDK_AAC" ]; then
            cat > "$CWD/pkgconfig_temp/fdk-aac.pc" <<EOF
prefix=$FDK_AAC
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include
Name: fdk-aac
Description: Fraunhofer FDK AAC library
Version: 2.0.2
Libs: -L\${libdir} -lfdk-aac
Cflags: -I\${includedir}
EOF
        fi
        if [ "$DAV1D" ]; then
            cat > "$CWD/pkgconfig_temp/dav1d.pc" <<EOF
prefix=$DAV1D
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include
Name: dav1d
Description: AV1 decoding library
Version: 1.5.3
Libs: -L\${libdir} -ldav1d
Cflags: -I\${includedir}
EOF
        fi
        if [ "$LAME" ]; then
            cat > "$CWD/pkgconfig_temp/lame.pc" <<EOF
prefix=$LAME
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include
Name: lame
Description: MP3 encoding library
Version: 3.100
Libs: -L\${libdir} -lmp3lame
Cflags: -I\${includedir}
EOF
        fi
        if [ "$OPUS" ]; then
            cat > "$CWD/pkgconfig_temp/opus.pc" <<EOF
prefix=$OPUS
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include
Name: opus
Description: Opus audio codec
Version: 1.4
Libs: -L\${libdir} -lopus
Cflags: -I\${includedir}/opus
EOF
        fi
        if [ "$VPX" ]; then
            cat > "$CWD/pkgconfig_temp/vpx.pc" <<EOF
prefix=$VPX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include
Name: vpx
Description: VP8/VP9 video codec
Version: 1.13.0
Libs: -L\${libdir} -lvpx
Cflags: -I\${includedir}
EOF
        fi
        if [ "$OGG" ]; then
            cat > "$CWD/pkgconfig_temp/ogg.pc" <<EOF
prefix=$OGG
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include
Name: ogg
Description: ogg library
Version: 1.3.5
Libs: -L\${libdir} -logg
Cflags: -I\${includedir}
EOF
        fi
        if [ "$VORBIS" ]; then
            cat > "$CWD/pkgconfig_temp/vorbis.pc" <<EOF
prefix=$VORBIS
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include
Name: vorbis
Description: vorbis library
Version: 1.3.7
Requires: ogg
Libs: -L\${libdir} -lvorbis -lvorbisenc -lvorbisfile
Cflags: -I\${includedir}
EOF
            cp "$CWD/pkgconfig_temp/vorbis.pc" "$CWD/pkgconfig_temp/vorbisenc.pc"
            cp "$CWD/pkgconfig_temp/vorbis.pc" "$CWD/pkgconfig_temp/vorbisfile.pc"
        fi
        if [ "$THEORA" ]; then
            cat > "$CWD/pkgconfig_temp/theora.pc" <<EOF
prefix=$THEORA
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include
Name: theora
Description: theora library
Version: 1.1.1
Requires: ogg
Libs: -L\${libdir} -ltheora -ltheoradec -ltheoraenc
Cflags: -I\${includedir}
EOF
            cp "$CWD/pkgconfig_temp/theora.pc" "$CWD/pkgconfig_temp/theoradec.pc"
            cp "$CWD/pkgconfig_temp/theora.pc" "$CWD/pkgconfig_temp/theoraenc.pc"
        fi

        mkdir -p "$SCRATCH/$ARCH"
        cd "$SCRATCH/$ARCH"

        CFLAGS="-arch $ARCH"
        if [ "$ARCH" = "i386" -o "$ARCH" = "x86_64" ]; then
            PLATFORM="iPhoneSimulator"
            CFLAGS="$CFLAGS -mios-simulator-version-min=$DEPLOYMENT_TARGET"
        else
            PLATFORM="iPhoneOS"
            CFLAGS="$CFLAGS -mios-version-min=$DEPLOYMENT_TARGET -fembed-bitcode"
            if [ "$ARCH" = "arm64" ]; then EXPORT="GASPP_FIX_XCODE5=1"; fi
        fi

        XCRUN_SDK=`echo $PLATFORM | tr '[:upper:]' '[:lower:]'`
        CC="xcrun -sdk $XCRUN_SDK clang"

        if [ "$ARCH" = "arm64" ]; then
            AS="gas-preprocessor.pl -arch aarch64 -- $CC"
        else
            AS="gas-preprocessor.pl -- $CC"
        fi

        LDFLAGS="$CFLAGS"
        
        # 针对 x265 增加 C++ 链接标志
        if [ "$X265" ]; then
            LDFLAGS="$LDFLAGS -lc++"
        fi

        # Manually add paths for libraries that might not use pkg-config or need explicit flags
        if [ "$X264" ]; then
            CFLAGS="$CFLAGS -I$X264/include"
            LDFLAGS="$LDFLAGS -L$X264/lib"
        fi
        if [ "$X265" ]; then
            CFLAGS="$CFLAGS -I$X265/include"
            LDFLAGS="$LDFLAGS -L$X265/lib"
        fi
        if [ "$FDK_AAC" ]; then
            CFLAGS="$CFLAGS -I$FDK_AAC/include"
            LDFLAGS="$LDFLAGS -L$FDK_AAC/lib"
        fi
        if [ "$DAV1D" ]; then
            CFLAGS="$CFLAGS -I$DAV1D/include"
            LDFLAGS="$LDFLAGS -L$DAV1D/lib"
        fi
        if [ "$LAME" ]; then
            CFLAGS="$CFLAGS -I$LAME/include"
            LDFLAGS="$LDFLAGS -L$LAME/lib"
        fi
        if [ "$OPUS" ]; then
            CFLAGS="$CFLAGS -I$OPUS/include/opus"
            LDFLAGS="$LDFLAGS -L$OPUS/lib"
        fi
        if [ "$VPX" ]; then
            CFLAGS="$CFLAGS -I$VPX/include"
            LDFLAGS="$LDFLAGS -L$VPX/lib"
        fi
        if [ "$OGG" ]; then
            CFLAGS="$CFLAGS -I$OGG/include"
            LDFLAGS="$LDFLAGS -L$OGG/lib"
        fi
        if [ "$VORBIS" ]; then
            CFLAGS="$CFLAGS -I$VORBIS/include"
            LDFLAGS="$LDFLAGS -L$VORBIS/lib"
        fi
        if [ "$THEORA" ]; then
            CFLAGS="$CFLAGS -I$THEORA/include"
            LDFLAGS="$LDFLAGS -L$THEORA/lib"
        fi

        TMPDIR=${TMPDIR/%\/} $CWD/$SOURCE/configure \
            --target-os=darwin \
            --arch=$ARCH \
            --cc="$CC" \
            --as="$AS" \
            $CONFIGURE_FLAGS \
            --extra-cflags="$CFLAGS" \
            --extra-ldflags="$LDFLAGS" \
            --prefix="$THIN/$ARCH" || exit 1

        make -j3 install $EXPORT || exit 1
        cd $CWD
    done
fi

# ====================
# 合并库 (Lipo)
# ====================

if [ "$LIPO" ]; then
    echo "📦 Building fat binaries..."
    mkdir -p $FAT/lib
    set - $ARCHS
    CWD=`pwd`
    cd $THIN/$1/lib
    for LIB in *.a
    do
        cd $CWD
        lipo -create `find $THIN -name $LIB` -output $FAT/lib/$LIB || exit 1
    done
    cd $CWD
    cp -rf $THIN/$1/include $FAT
fi

echo "✅ FFmpeg Build Done!"