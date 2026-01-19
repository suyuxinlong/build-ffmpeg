# FFmpeg iOS & tvOS Build System (FFmpeg 7.1)

[中文版](README_CN.md)

> **Acknowledgement**: This project is based on and improved from [kewlbear/FFmpeg-iOS-build-script](https://github.com/kewlbear/FFmpeg-iOS-build-script).

This is a collection of highly automated shell scripts designed to solve various dependency hells, architecture merging, and assembly compatibility issues when cross-compiling FFmpeg for iOS and tvOS on macOS.

This project is based on the **FFmpeg 7.1** core, integrating mainstream codec libraries, and provides a one-click build solution for generating `XCFramework`-style (though standard Framework structure) packages, perfectly supporting Swift and Objective-C projects.

---

## 🚀 Quick Start

### 1. Environment Dependencies
Ensure that the necessary basic tools for compilation are installed:
```bash
brew install yasm nasm cmake
```
*Note: The script will automatically handle `gas-preprocessor.pl`, so manual installation is not required.*

### 2. Build iOS Version (Includes x264/hevc, etc.)
The integration of FFmpeg features follows the "dependencies first, core later" principle. The script automatically detects the outputs of dependency libraries in the same directory. Therefore, if you need specific library support, you **must** complete the compilation of the corresponding library before running `build-ffmpeg.sh`.

```bash
# 1. Compile the dependency libraries you need (Execute as needed)
# For example, if you need x265, you must run:
./build-x265.sh

# Similarly, if you need other libraries, execute the corresponding scripts first:
./build-x264.sh && ./build-fdk-aac.sh && ./build-dav1d.sh

# 2. Compile FFmpeg (Core Step)
# The script will automatically scan and integrate compiled directories like fat-x264, fat-x265, etc.
./build-ffmpeg.sh "arm64 x86_64"

# 3. Package as a Framework (Recommended)
./build-ffmpeg-iOS-framework.sh
```
> **Output**: `FFmpeg.framework` (Contains arm64 device + x86_64 simulator)

### 3. Build tvOS Version
The tvOS version aims for ultimate stability and **does not integrate** third-party libraries by default (to avoid complex cross-compilation errors), but it fully retains hardware decoding support.
```bash
./build-ffmpeg-tvos.sh
```
> **Output**: `FFmpeg-tvOS.framework` (Contains arm64 device + x86_64 simulator)

---

## 📦 Integration into Xcode Project

### 1. Import Framework
*   Drag and drop the generated `FFmpeg.framework` into your Xcode project directory.
*   In your target's **Build Phases** -> **Link Binary With Libraries**, ensure the Framework has been added.
*   **Critical Setting**: In **General** -> **Frameworks, Libraries, and Embedded Content**, set the Embed option for `FFmpeg.framework` to **Do Not Embed** (since this is a Framework encapsulated from static libraries, embedding will cause signature errors).

### 2. Add System Dependencies
FFmpeg depends on the following iOS/macOS system libraries, which must be manually added to the **Link Binary With Libraries** list; otherwise, you will encounter `Undefined symbol` errors:
*   `libz.tbd` (Zlib compression support)
*   `libbz2.tbd` (Bzip2 compression support)
*   `libiconv.tbd` (Character set conversion)
*   `AudioToolbox.framework` (Audio processing)
*   `VideoToolbox.framework` (Hardware decoding support)
*   `CoreMedia.framework` (Basic media types)
*   `AVFoundation.framework` (Audio/Video foundation framework)
*   *(If compiling on older Xcode versions)* `libc++.tbd`

### 3. Header References
It is recommended to set **Header Search Paths** for easier header referencing:
1.  In **Build Settings** -> **Search Paths** -> **Header Search Paths**, add:
    `$(PROJECT_DIR)/FFmpeg.framework/Headers`
2.  Reference in code:
    ```c
    #include "libavcodec/avcodec.h"
    #include "libavformat/avformat.h"
    // Or (if using Modules)
    // @import FFmpeg;
    ```

---

## 🔬 Core Technical Implementation Principles (Technical Deep Dive)

This set of scripts is not just a simple call to `configure` and `make`. It includes a series of "black magic" fixes and optimizations for the iOS/tvOS compilation environment.

### 1. Intelligent Dependency Injection (`pkg-config` Hijacking Technology)
The FFmpeg build system relies heavily on `pkg-config` to find third-party libraries (such as x264, x265). In a cross-compilation environment, getting FFmpeg to correctly find the iOS static libraries we just compiled (rather than the macOS libraries installed on the system) is a major pain point.

**Script Solution (`build-ffmpeg.sh`):**
*   **Virtual Environment**: The script dynamically creates a fake `pkg-config` script in the `tools_bin/` directory.
*   **Path Redirection**: When FFmpeg requests the path for `x264`, this fake script intercepts the request and forcibly returns the header file and library paths from our local `fat-x264/` directory.
*   **Advantage**: This completely solves the `Package xxxxx was not found` problem without polluting the system's environment variables.

### 2. Assembly Code Compatibility Handling (Assembly & Bitcode)
FFmpeg contains a large amount of assembly code optimized for specific CPUs, but this often throws errors on the iOS Clang compiler.

*   **Gas-Preprocessor**: The script automatically detects and downloads `gas-preprocessor.pl`, a Perl script used to convert GNU Assembler (GAS) syntax into Apple Clang compatible syntax.
*   **VVC Module Masking**: The VVC (H.266) decoder introduced in FFmpeg 7.1 contains a large amount of new AArch64 assembly, which currently has compatibility issues with the iOS cross-compilation toolchain. The script automatically avoids this compilation error via `--disable-vvc`, ensuring the overall build succeeds.
*   **Bitcode Support**: The `-fembed-bitcode` flag is enabled by default, ensuring the compiled static libraries contain Bitcode segments (although Xcode 14+ has deprecated it, it is kept for compatibility with older projects).

### 3. Modern Framework Encapsulation
Traditional scripts usually only generate `.a` files. This project's `build-ffmpeg-iOS-framework.sh` script does more:

*   **Libtool Merging**: Uses `libtool -static` instead of the traditional `ar` for more reliable symbol table handling.
*   **Module Map**: Automatically generates a `module.modulemap` file, allowing direct use of `import FFmpeg` in Swift projects without the need for a cumbersome `Bridging-Header.h`.
*   **Umbrella Header**: Automatically generates an `FFmpeg.h` umbrella header file to unify reference management.

### 4. Special Handling for tvOS
The tvOS SDK (`appletvos`) has stripped many system APIs (such as some CoreAudio functions) compared to iOS.
*   **Targeted Disabling**: `build-ffmpeg-tvos.sh` explicitly disables `--disable-outdev=audiotoolbox` and `--disable-indev=avfoundation` to prevent link failures caused by calling non-existent APIs.
*   **VideoToolbox Retention**: Although the system libraries are streamlined, the script carefully retains the `VideoToolbox` module, ensuring Apple TV 4K can utilize hardware decoding for H.264 and HEVC.

---

## ⚙️ Advanced Customization (Configuration)

You can customize the build behavior by modifying the variables at the top of the scripts.

### Modify FFmpeg Version
In `build-ffmpeg.sh` or `build-ffmpeg-tvos.sh`:
```bash
FF_VERSION="7.1"  # Change to the version you need, e.g., "6.1"
```
*Note: If you change the version, you may need to manually check if new features like VVC need to be disabled.*

### Modify Supported Architectures
If you only need the device version (to reduce package size), you can modify the script:
```bash
ARCHS="arm64" # Remove x86_64
```

### Prune FFmpeg Modules
FFmpeg enables a large number of rare codecs by default, which leads to a larger Framework size (usually between 50MB-100MB). You can significantly reduce the size by modifying the `CONFIGURE_FLAGS` variable.

**Strategy A: Disable Encoders and Muxers (Recommended, reduces size by ~40%)**
Most Apps only need playback (decoding) and do not need recording or transcoding (encoding). Disabling all encoders and muxers is the simplest and lowest-risk way to slim down:
```bash
CONFIGURE_FLAGS="... --disable-encoders --disable-muxers"
```

**Strategy B: Disable Unnecessary Filters**
If you don't involve complex video post-processing (like watermarks or cropping), you can disable the bulky filter system and only keep the necessary pixel format conversion functions:
```bash
CONFIGURE_FLAGS="... --disable-filters --enable-filter=scale,format,null"
```

**Strategy C: "Minimalism" with External Libraries**
Third-party libraries are powerful but come with a significant size cost. Weigh the options before integration:
*   **x265 (HEVC Encoding)**: Adds about 5MB-8MB. If you only play H.265, use the system hardware decoder instead.
*   **dav1d (AV1 Decoding)**: Adds about 3MB-5MB. AV1 is a future trend, but hardware decoding is not yet universal on mobile.
*   **fdk-aac**: Adds about 1MB. Good quality but has licensing risks; usually, the system's built-in AAC decoding is sufficient.

**Strategy D: Enable Link-Time Optimization (LTO)**
Add `--enable-lto` to `CONFIGURE_FLAGS`. The compiler will perform global optimizations during the linking stage, removing redundant code that is unused across files.
*Note: Enabling LTO significantly increases compilation time but can further compress the binary size by 5%-10%.*

**Strategy E: Minimalist Whitelist Mode (Extreme Slimming, Size < 15MB)**
Adopts a "disable everything first, then enable as needed" strategy.
Below is an example configuration for H.264/H.265/AAC hardware-accelerated playback only:
```bash
CONFIGURE_FLAGS="--disable-everything \
                 --enable-decoder=h264,hevc,aac \
                 --enable-demuxer=mov,m4v,mp4 \
                 --enable-parser=h264,hevc,aac \
                 --enable-protocol=file,http,https,tls,tcp \
                 --enable-hwaccel=h264_videotoolbox,hevc_videotoolbox \
                 --enable-filter=scale,format,null"
```

#### 💡 Size Reference Table (arm64 Architecture)
| Configuration | Estimated Framework Size | Use Case |
| :--- | :--- | :--- |
| **Full Featured** (inc. x264/x265) | 80MB+ | Video editing, full-format players |
| **Playback Only** (no encoders/filters) | 40MB - 50MB | General short video, livestream Apps |
| **HW-Accel Whitelist** | 12MB - 18MB | Minimalist player, H.264 monitoring |
| **Single Arch (No x86_64)** | Reduces ~45% | Final App Store release version |

---

## 🔧 Dependency Management & Build Internals

To achieve "out-of-the-box" functionality and avoid common cross-compilation pitfalls, the scripts include a set of intelligent dependency searching and build repair mechanisms.

### 1. Automatic Dependency Detection (`build-ffmpeg.sh`)
The script does not force dependency libraries to be in a specific path but uses a dynamic scanning mechanism. When running `build-ffmpeg.sh`:
1.  **Environment Variable Priority**: If you want to use a library you compiled yourself, you can override it by setting environment variables.
    ```bash
    # Example: Forcing the use of x264 from a specific path
    export X264="/Users/dev/my-custom-x264"
    ./build-ffmpeg.sh
    ```
2.  **Automatic Directory Scanning**: If no environment variables are set, the script automatically searches for standard-named folders in the **current directory** (`.`) and the **parent directory** (`..`):
    *   **x264**: Looks for `fat-x264`, `x264-ios`, `x264`
    *   **x265**: Looks for `fat-x265`, `x265-ios`, `x265`
    *   **fdk-aac**: Looks for `fdk-aac-ios`, `fdk-aac`, `fat-fdk-aac`
    *   **dav1d**: Looks for `fat-dav1d`, `dav1d-ios`, `dav1d`

### 2. Special Build Handling for Modules
*   **x265 (CMake)**:
    *   **Automatic Patching**: `build-x265.sh` automatically modifies `CMakeLists.txt` in the source code to remove outdated policy settings (CMP0025, CMP0054) and upgrade minimum version requirements, fixing configuration errors in modern CMake environments.
    *   **Disabling Assembly**: Forcibly sets `-DENABLE_ASSEMBLY=OFF` for the iOS platform, solving some missing linker symbol issues.
*   **dav1d (Meson/Ninja)**:
    *   **Dynamic Cross-files**: `build-dav1d.sh` generates the `cross-file` required by Meson (e.g., `dav1d-cross-arm64.txt`) in real-time based on the current Xcode SDK path, ensuring that compiler and linker flags match perfectly.
*   **x264**:
    *   **Simulator Compatibility**: When compiling the `x86_64` (simulator) version, the script automatically adds `--disable-asm`. This is to avoid relocation errors that old x264 assembly code might produce under newer macOS linkers, while the device (`arm64`) version still retains assembly optimization.
*   **FFmpeg VVC (H.266)**:
    *   **Temporary Masking**: Since the new VVC decoder in FFmpeg 7.1 contains a large amount of AArch64 assembly that is not yet fully adapted to the iOS toolchain, `build-ffmpeg.sh` disables it by default via `--disable-decoder=vvc` to ensure overall build success.

---

## 📂 Directory Structure

After executing all scripts, the directory structure is as follows:

```text
├── FFmpeg.framework/        # [Final Output] iOS Framework
├── FFmpeg-tvOS.framework/   # [Final Output] tvOS Framework
├── FFmpeg-iOS/              # iOS original static libraries and headers
├── fat-x264/                # x264 universal static library
├── fat-x265/                # x265 universal static library
├── tools_bin/               # Temporary compilation tools (gas-preprocessor, pkg-config)
├── thin/                    # Intermediate artifacts for single architectures (arm64, x86_64 separated)
├── scratch/                 # Temporary object files during compilation (can be deleted anytime)
└── build-*.sh               # Build scripts
```

---

## 📜 Script Descriptions

| Script Name | Description |
| :--- | :--- |
| **`build-ffmpeg.sh`** | **Core Script**. Handles FFmpeg source download, multi-arch cross-compilation, and automatic integration of x264/x265/aac/dav1d libraries. |
| **`build-ffmpeg-iOS-framework.sh`** | Packages the `.a` static libraries generated by `build-ffmpeg.sh` into a standard iOS `.framework`, generating Module Map and Umbrella Header. |
| **`build-ffmpeg-tvos.sh`** | Compilation script specifically for Apple TV (tvOS), disabling incompatible APIs and maintaining a lightweight build. |
| **`build-x264.sh`** | Downloads and compiles x264 (H.264) static libraries for iOS. |
| **`build-x265.sh`** | Downloads and compiles x265 (HEVC/H.265) static libraries for iOS. Includes compatibility patches for modern CMake. |
| **`build-fdk-aac.sh`** | Downloads and compiles the fdk-aac audio codec library for iOS. |
| **`build-dav1d.sh`** | Downloads and compiles the dav1d (AV1) decoding library for iOS. |
| **`clean.sh`** | Cleanup script. Removes all build artifacts (thin, fat, scratch directories), temporary tools, and downloaded source packages. |

---

## ⚠️ Common Issues Troubleshooting

1.  **Symbol not found: _xxx**
    *   If you encounter linking errors at runtime, check if the Xcode `Link Binary With Libraries` has added the necessary system libraries: `libc++.tbd`, `libz.tbd`, `libiconv.tbd`, `VideoToolbox`, `AudioToolbox`.

2.  **Xcode cannot index header files**
    *   Ensure the path where the Framework is located does not contain spaces or special characters.
    *   Add `$(PROJECT_DIR)/FFmpeg.framework/Headers` to `Header Search Paths`.

3.  **App Store Upload Warning (Simulator Architecture)**
    *   The generated Framework contains the `x86_64` simulator architecture. When archiving and uploading to the App Store, Xcode usually strips it automatically. If you encounter errors, you can manually remove it using the `lipo` command:
    ```bash
    lipo -remove x86_64 FFmpeg.framework/FFmpeg -output FFmpeg.framework/FFmpeg
    ```

---

## 📜 License

The script source code follows the MIT license.
**Important Note**: The license of the compiled FFmpeg binary depends on the modules you enable.
*   Enable `x264`/`x265` -> **GPL** (Requires your App to also be open source).
*   Enable `fdk-aac` -> **Non-Free** (Incompatible with GPL, generally not distributable, limited to personal study/research or commercial licensing).
*   Compile default FFmpeg only -> **LGPL** (Allows use in commercial Apps via dynamic linking or static linking + providing object files).

---

## 💻 Hardware Compatibility

*   **Apple Silicon (M1/M2/M3/M4/M5)**: Fully verified in this environment, supporting native compilation.
*   **Intel Chips**: Theoretically supported but has not been fully verified in a real-world build environment yet. If you encounter issues on an Intel Mac, please feel free to provide feedback.