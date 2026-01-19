# FFmpeg iOS & tvOS 编译构建系统 (FFmpeg 7.1)

[English Version](README.md)

> **致谢**: 本项目基于并改进自 [kewlbear/FFmpeg-iOS-build-script](https://github.com/kewlbear/FFmpeg-iOS-build-script)。

这是一个高度自动化的 Shell 脚本集合，旨在解决在 macOS 上为 iOS 和 tvOS 交叉编译 FFmpeg 时面临的各种依赖地狱、架构合并和汇编兼容性问题。

本项目基于 **FFmpeg 7.1** 核心，集成了主流编解码库，并提供了一键生成 `XCFramework` 风格（虽然是标准 Framework 结构）的构建方案，完美支持 Swift 和 Objective-C 项目。

---

## 🚀 快速上手

### 1. 环境依赖
确保安装了编译所需的基础工具：
```bash
brew install yasm nasm cmake
```
*注：脚本会自动处理 `gas-preprocessor.pl`，无需手动安装。*

### 2. 构建 iOS 版本 (包含 x264/hevc 等)
FFmpeg 的功能集成遵循“先依赖后核心”的原则。脚本会自动检测同级目录下的依赖库产物，因此如果你需要特定的库支持，**必须**在运行 `build-ffmpeg.sh` 之前先完成相应库的编译。

```bash
# 1. 编译你需要的依赖库 (按需执行)
# 例如，如果需要 x265，则必须先运行：
./build-x265.sh

# 同理，如果需要其他库，请先执行对应的脚本：
./build-x264.sh && ./build-fdk-aac.sh && ./build-dav1d.sh

# 新增音视频库支持：
./build-ogg.sh && ./build-vorbis.sh && ./build-theora.sh
./build-opus.sh && ./build-lame.sh && ./build-vpx.sh

# 2. 编译 FFmpeg (核心步骤)
# 脚本会自动扫描并集成已编译好的 fat-x264, fat-x265, fat-vpx 等目录
./build-ffmpeg.sh "arm64 x86_64"

# 3. 打包为 Framework (推荐)
./build-ffmpeg-iOS-framework.sh
```
> **产物**: `FFmpeg.framework` (包含 arm64 设备 + x86_64 模拟器)

### 3. 构建 tvOS 版本
tvOS 版本追求极致的稳定性，默认**不集成**第三方库（避免复杂的交叉编译错误），但完整保留了硬解支持。
```bash
./build-ffmpeg-tvos.sh
```
> **产物**: `FFmpeg-tvOS.framework` (包含 arm64 设备 + x86_64 模拟器)

---

## 📦 集成到 Xcode 工程

### 1. 导入 Framework
*   将生成的 `FFmpeg.framework` 拖入 Xcode 工程目录。
*   在 target 的 **Build Phases** -> **Link Binary With Libraries** 中确保已添加该 Framework。
*   **无需额外库**: 由于 Framework 已包含所有启用的第三方库（如 x264, LAME）的符号，您**不需要**再手动导入这些库的 `.a` 文件。
*   **关键设置**: 在 **General** -> **Frameworks, Libraries, and Embedded Content** 中，将 `FFmpeg.framework` 的 Embed 选项设置为 **Do Not Embed**。

### 2. 添加系统依赖库
FFmpeg 依赖以下 iOS/macOS 系统库，必须手动添加到 **Link Binary With Libraries** 列表中，否则会报错 `Undefined symbol`：
*   `libz.tbd` (Zlib 压缩支持)
*   `libbz2.tbd` (Bzip2 压缩支持)
*   `libiconv.tbd` (字符集转换)
*   `AudioToolbox.framework` (音频处理)
*   `VideoToolbox.framework` (硬解支持)
*   `CoreMedia.framework` (基础媒体类型)
*   `AVFoundation.framework` (音视频基础框架)
*   *(如果在旧版 Xcode 编译)* `libc++.tbd`

### 3. 头文件引用
推荐设置 **Header Search Paths** 以便更方便地引用头文件：
1.  在 **Build Settings** -> **Search Paths** -> **Header Search Paths** 中添加：
    `$(PROJECT_DIR)/FFmpeg.framework/Headers`
2.  在代码中引用：
    ```c
    #include "libavcodec/avcodec.h"
    #include "libavformat/avformat.h"
    // 或者 (如果使用了 Module)
    // @import FFmpeg;
    ```



---

## 🔬 核心技术实现原理 (Technical Deep Dive)

本套脚本不仅仅是简单的 `configure` 和 `make` 调用，它包含了一系列针对 iOS/tvOS 编译环境的“黑科技”修复与优化。

### 1. 依赖库的智能注入 (`pkg-config` 劫持技术)
FFmpeg 的构建系统极其依赖 `pkg-config` 来查找第三方库（如 x264, x265）。在交叉编译环境中，让 FFmpeg 正确找到我们刚刚编译好的 iOS 静态库（而不是系统安装的 macOS 库）是一个巨大的痛点。

**脚本解决方案 (`build-ffmpeg.sh`):**
*   **虚拟环境**: 脚本会在 `tools_bin/` 目录下动态创建一个伪造的 `pkg-config` 脚本。
*   **路径重定向**: 当 FFmpeg 请求 `x264` 的路径时，这个伪造脚本会拦截请求，并强制返回我们本地 `fat-x264/` 目录下的头文件和库路径。
*   **优势**: 彻底解决了 `Package xxxxx was not found` 的问题，且无需污染系统的环境变量。

### 2. 汇编代码的兼容性处理 (Assembly & Bitcode)
FFmpeg 包含了大量针对特定 CPU 优化的汇编代码，但这在 iOS Clang 编译器上经常报错。

*   **Gas-Preprocessor**: 脚本会自动检测并下载 `gas-preprocessor.pl`，这是一个 Perl 脚本，用于将 GNU 汇编器 (GAS) 语法转换为 Apple Clang 兼容的语法。
*   **VVC 模块屏蔽**: FFmpeg 7.1 引入的 VVC (H.266) 解码器包含大量新的 AArch64 汇编，目前与 iOS 交叉编译工具链存在兼容性问题。脚本通过 `--disable-vvc` 自动规避了此编译错误，确保整体构建成功。
*   **Bitcode 支持**: 默认开启 `-fembed-bitcode` 标志，确保编译出的静态库包含 Bitcode 段（尽管 Xcode 14 已弃用，但为了兼容旧项目仍保留）。

### 3. 现代化的 Framework 封装
传统的脚本通常只生成 `.a` 文件。本项目的 `build-ffmpeg-iOS-framework.sh` 脚本做了更多工作：

*   **一体化二进制文件**: 使用 `libtool -static` 将**所有**编译好的静态库（包括 FFmpeg 核心和已启用的第三方库，如 x264、LAME 等）合并为 Framework 内的一个单一可执行文件。这意味着您无需在项目中链接多个 `.a` 文件。
*   **Module Map**: 自动生成 `module.modulemap` 文件，允许在 Swift 项目中直接使用 `import FFmpeg`。
*   **伞头文件 (Umbrella Header)**: 自动生成 `FFmpeg.h` 伞头文件。

### 4. tvOS 的特殊处理
tvOS 版本旨在实现最大的稳定性，并遵循**极简原则**：
*   **不集成第三方库**: 为了避免复杂的链接错误以及由于受限 API 可能导致的 App Store 被拒，`build-ffmpeg-tvos.sh` 不集成任何第三方编解码器（如 x264/x265）。它完全依赖 FFmpeg 的内置解码器和系统级硬件加速。
*   **有针对性的裁剪**: 显式禁用 `--disable-swscale-alpha` 和其他模块，以确保在 Apple TV 平台上的最佳性能。

### 5. 老旧库的现代环境适配 (Theora/Vorbis/LAME)
许多经典的开源库（如 libtheora, libvorbis）其构建系统较为陈旧，无法直接识别 `arm64-apple-ios` 架构。
*   **自动补丁**: `build-theora.sh` 和 `build-vorbis.sh` 会自动检测并从 GNU 官方下载最新的 `config.guess` 和 `config.sub`，并使用 `sed` 移除过时的 `-force_cpusubtype_ALL` 链接标志，解决了现代 Xcode 链接器报错的问题。
*   **依赖链管理**: 针对 Ogg 家族，脚本严格遵循 `libogg -> libvorbis/libtheora` 的顺序，并自动在 `configure` 阶段注入正确的头文件搜索路径。

### 6. libvpx 的特殊 Target 映射
libvpx (VP8/VP9) 拥有自己独立的配置系统。
*   **Target 转换**: 脚本自动将 iOS 的 `arm64` 和 `x86_64` 架构映射为 libvpx 特有的 `arm64-darwin20-gcc` 和 `x86_64-darwin20-gcc` 目标。
*   **高位深支持**: 默认开启 `--enable-vp9-highbitdepth`，以支持更专业的视频回放需求。

## ⚙️ 高级自定义 (Configuration)

您可以通过修改脚本头部的变量来定制构建行为。

### 修改 FFmpeg 版本
在 `build-ffmpeg.sh` 或 `build-ffmpeg-tvos.sh` 中：
```bash
FF_VERSION="7.1"  # 修改为您需要的版本，如 "6.1"
```
*注意：如果修改版本，可能需要手动检查 VVC 等新特性是否需要禁用。*

### 修改支持的架构
如果您只需要真机版本（减小包体积），可以在脚本中修改：
```bash
ARCHS="arm64" # 删除 x86_64
```

### 裁剪 FFmpeg 模块
FFmpeg 默认开启了大量罕见的编解码器，这会导致生成的 Framework 体积较大（通常在 50MB-100MB 之间）。通过修改 `CONFIGURE_FLAGS` 变量，您可以大幅瘦身。

**策略 A：禁用编码器与复用器（推荐，减小约 40%）**
绝大多数 App 只需要播放（解码），不需要录制或转码（编码）。禁用所有编码器和复用器是最简单且风险最低的瘦身方式：
```bash
CONFIGURE_FLAGS="... --disable-encoders --disable-muxers"
```

**策略 B：禁用非必要滤镜**
如果不涉及复杂的视频后期处理（如水印、裁剪），可以禁用庞大的滤镜系统，仅保留必要的像素格式转换功能：
```bash
CONFIGURE_FLAGS="... --disable-filters --enable-filter=scale,format,null"
```

**策略 C：外部库的“断舍离”**
第三方库虽然功能强大，但体积代价巨大。集成前请权衡：
*   **x265 (HEVC 编码)**: 约增加 5MB-8MB。如果只播放 H.265，使用系统硬解即可，无需集成该库。
*   **dav1d (AV1 解码)**: 约增加 3MB-5MB。AV1 是未来趋势，但目前移动端硬解普及率一般，若非强制要求建议不加。
*   **fdk-aac**: 约增加 1MB。音质好但有许可证风险，通常系统自带的 AAC 解码已足够。

**策略 D：开启链接时优化 (LTO)**
在 `CONFIGURE_FLAGS` 中加入 `--enable-lto`。编译器会在链接阶段进行全局优化，剔除跨文件未使用的冗余代码。
*注：开启 LTO 会显著增加编译时间，但能进一步压缩 5%-10% 的二进制体积。*

**策略 E：极简白名单模式（深度瘦身，体积 < 15MB）**
采用“先全部禁用，再按需开启”的策略，适合对包体积极其敏感的场景。
以下是一个仅支持 H.264/H.265/AAC 硬解播放的配置示例：
```bash
CONFIGURE_FLAGS="--disable-everything \
                 --enable-decoder=h264,hevc,aac \
                 --enable-demuxer=mov,m4v,mp4 \
                 --enable-parser=h264,hevc,aac \
                 --enable-protocol=file,http,https,tls,tcp \
                 --enable-hwaccel=h264_videotoolbox,hevc_videotoolbox \
                 --enable-filter=scale,format,null"
```

#### 💡 体积参考表 (arm64 架构)
| 配置方案 | 预计 Framework 体积 | 适用场景 |
| :--- | :--- | :--- |
| **全功能版** (含 x264/x265/VP9/AV1/Opus/LAME) | 100MB+ | 专业视频剪辑、全格式全能播放器 |
| **通用音视频版** (含 x264/AAC/MP3/Opus) | 60MB - 80MB | 主流社交、短视频 App |
| **仅播放版** (禁用编码/滤镜) | 40MB - 50MB | 通用短视频、直播 App |
| **硬解白名单版** | 12MB - 18MB | 极简播放器、H.264 监控 |
| **单架构 (无 x86_64)** | 减小约 45% | 最终 App Store 发布版本 |

---

## 🔧 依赖库管理与构建细节 (Dependency Management & Build Internals)

为了实现“开箱即用”并规避常见的交叉编译坑，脚本内置了一套智能的依赖查找和构建修复机制。了解这些细节有助于您进行更深度的定制。

### 1. 依赖库自动检测机制 (`build-ffmpeg.sh`)
脚本不强制要求依赖库必须在特定路径，而是采用动态扫描机制。在运行 `build-ffmpeg.sh` 时：
1.  **环境变量优先**: 如果您希望使用自己编译的库，可以通过设置环境变量来覆盖。
    ```bash
    # 示例：强制使用指定路径的 x264
    export X264="/Users/dev/my-custom-x264"
    ./build-ffmpeg.sh
    ```
2.  **自动目录扫描**: 如果未设置环境变量，脚本会自动在**当前目录** (`.`) 和**上级目录** (`..`) 搜寻标准命名文件夹：
    *   **x264**: 查找 `fat-x264`, `x264-ios`, `x264`
    *   **x265**: 查找 `fat-x265`, `x265-ios`, `x265`
    *   **fdk-aac**: 查找 `fdk-aac-ios`, `fdk-aac`, `fat-fdk-aac`
    *   **dav1d**: 查找 `fat-dav1d`, `dav1d-ios`, `dav1d`
    *   **lame**: 查找 `fat-lame`, `lame-ios`
    *   **vpx**: 查找 `fat-vpx`, `libvpx-ios`
    *   **ogg/vorbis/theora**: 自动查找对应的 `fat-*` 目录

### 2. 各模块的特殊构建处理
*   **x265 (CMake)**:
    *   **自动 Patch**: `build-x265.sh` 会自动修改源码中的 `CMakeLists.txt`，移除过时的策略设置 (CMP0025, CMP0054) 并升级最低版本要求，以修复在现代 CMake 环境下的配置报错。
    *   **禁用汇编**: 针对 iOS 平台强制设置 `-DENABLE_ASSEMBLY=OFF`，解决了部分链接符号缺失的问题。
*   **dav1d (Meson/Ninja)**:
    *   **动态交叉文件**: `build-dav1d.sh` 会根据当前的 Xcode SDK 路径，实时生成 Meson 所需的 `cross-file` (例如 `dav1d-cross-arm64.txt`)，确保编译器和链接器标志完全匹配。
*   **x264**:
    *   **模拟器兼容性**: 在编译 `x86_64` (模拟器) 版本时，脚本自动添加了 `--disable-asm`。这是为了规避旧版 x264 汇编代码在 macOS 新版链接器下可能产生的重定位错误，而真机 (`arm64`) 版本依然保留汇编优化。
*   **FFmpeg VVC (H.266)**:
    *   **暂时屏蔽**: 鉴于 FFmpeg 7.1 新引入的 VVC 解码器中包含大量尚未完全适配 iOS 工具链的 AArch64 汇编代码，`build-ffmpeg.sh` 默认通过 `--disable-decoder=vvc` 将其禁用，以确保整体构建的成功率。

---

## 📂 目录结构说明

执行完所有脚本后，目录结构如下：

```text
├── FFmpeg.framework/        # [最终产物] iOS Framework
├── FFmpeg-tvOS.framework/   # [最终产物] tvOS Framework
├── FFmpeg-iOS/              # iOS 原始静态库和头文件
├── fat-x264/                # x264 通用静态库
├── fat-x265/                # x265 通用静态库
├── tools_bin/               # 存放临时编译工具 (gas-preprocessor, pkg-config)
├── thin/                    # 存放单架构的中间产物 (arm64, x86_64 分离)
├── scratch/                 # 编译时的临时对象文件 (可随时删除)
└── build-*.sh               # 构建脚本
```

---

## 📜 脚本功能详解 (Script Descriptions)

| 脚本文件名 | 功能描述 |
| :--- | :--- |
| **`build-ffmpeg.sh`** | **核心脚本**。负责下载 FFmpeg 源码，进行多架构交叉编译，并自动集成同级目录下的 x264/x265/aac/dav1d 库。 |
| **`build-ffmpeg-iOS-framework.sh`** | 将 `build-ffmpeg.sh` 生成的 `.a` 静态库打包成标准的 iOS `.framework`，并自动生成 Module Map 和伞头文件。 |
| **`build-ffmpeg-tvos.sh`** | 专门针对 Apple TV (tvOS) 平台的编译脚本，禁用了不兼容的 API 并保持轻量化。 |
| **`build-x264.sh`** | 下载并编译适用于 iOS 的 x264 (H.264) 静态库。 |
| **`build-x265.sh`** | 下载并编译适用于 iOS 的 x265 (HEVC/H.265) 静态库。包含对现代 CMake 的兼容性补丁。 |
| **`build-fdk-aac.sh`** | 下载并编译适用于 iOS 的 fdk-aac 音频编解码库。 |
| **`build-dav1d.sh`** | 下载并编译适用于 iOS 的 dav1d (AV1) 解码库。 |
| **`build-lame.sh`** | 下载并编译适用于 iOS 的 LAME (MP3 编码) 库。 |
| **`build-vpx.sh`** | 下载并编译 libvpx 库，支持 VP8 和 VP9 编解码。 |
| **`build-ogg.sh`** | 下载并编译 libogg 基础库，是 Vorbis/Theora 的前提。 |
| **`build-vorbis.sh`** | 下载并编译 libvorbis (Ogg Vorbis 音频) 库。 |
| **`build-theora.sh`** | 下载并编译 libtheora (Ogg Theora 视频) 库。 |
| **`build-opus.sh`** | 下载并编译 libopus (Opus 低延迟音频) 库。 |
| **`clean.sh`** | 一键清理脚本。删除所有编译产物（thin, fat, scratch 目录）、临时工具及下载的源码包。 |

---

## ⚠️ 常见问题排查

1.  **Symbol not found: _xxx**
    *   如果在运行时遇到链接错误，请检查 Xcode 的 `Link Binary With Libraries` 是否添加了必要的系统库：`libc++.tbd`, `libz.tbd`, `libiconv.tbd`, `VideoToolbox`, `AudioToolbox`。

2.  **Xcode 无法索引头文件**
    
    *   确保 Framework 所在的路径没有包含空格或特殊字符。
    *   在 `Header Search Paths` 中添加 `$(PROJECT_DIR)/FFmpeg.framework/Headers`。
    
3.  **App Store 上架警告 (模拟器架构)**
    *   生成的 Framework 包含 `x86_64` 模拟器架构。在 Archive 打包上传 App Store 时，Xcode 通常会自动剥离。如果遇到错误，可以使用 `lipo` 命令手动剔除：
    ```bash
    lipo -remove x86_64 FFmpeg.framework/FFmpeg -output FFmpeg.framework/FFmpeg
    ```

---

## 📜 许可证

脚本源码遵循 MIT 协议。
**重要提示**：编译生成的 FFmpeg 二进制文件的许可证取决于您启用的模块。
*   启用 `x264`/`x265` -> **GPL** (要求您的 App 也必须开源)。
*   启用 `fdk-aac` -> **Non-Free** (不兼容 GPL，通常不可分发，仅限个人学习研究或获得商业授权)。
*   仅编译默认 FFmpeg -> **LGPL** (允许在商业 App 中通过动态链接或静态链接+提供对象文件的方式使用)。

---

## 💻 硬件兼容性

*   **Apple Silicon (M1/M2/M3/M4/M5)**: 已在该环境下经过完整验证，支持原生编译。
*   **Intel 芯片**: 理论上支持，但尚未在实际环境中进行完整构建验证。如果您在 Intel Mac 上遇到问题，欢迎反馈。
