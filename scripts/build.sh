#!/bin/bash
# CloudAudiobook 构建脚本 v1.0
# 用法: ./scripts/build.sh [windows|android|linux|all] [debug|profile|release]
# 默认: ./scripts/build.sh all release

set -e

PLATFORM="${1:-all}"
MODE="${2:-release}"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_APPS_DIR="$PROJECT_ROOT/../app"

cd "$PROJECT_ROOT"

echo "========================================"
echo "  云听书 CloudAudiobook 构建脚本"
echo "  平台: $PLATFORM  模式: $MODE"
echo "========================================"

# 清理旧的构建产物
clean_build() {
    echo "[清理] 清除旧的构建产物..."
    flutter clean > /dev/null 2>&1 || true
    rm -rf build/
}

# 获取依赖
get_deps() {
    echo "[依赖] 获取 Flutter 依赖..."
    flutter pub get
}

# Windows 构建
build_windows() {
    local mode="$1"
    echo "[Windows] 构建 $mode 版本..."

    # 确保 mpv 文件存在
    local mpv_file="build/windows/x64/mpv-dev-x86_64-20230924-git-652a1dd.7z"
    if [ ! -f "$mpv_file" ]; then
        echo "[Windows] 下载 mpv 音频库..."
        mkdir -p build/windows/x64
        curl -L -o "$mpv_file" \
            "https://github.com/media-kit/libmpv-win32-audio-build/releases/download/2023-09-24/mpv-dev-x86_64-20230924-git-652a1dd.7z"
    fi

    flutter build windows --"$mode"

    # 归档
    local dest="$BUILD_APPS_DIR/${MODE^}/windows"
    mkdir -p "$dest"
    rm -rf "$dest/"*
    cp -r "build/windows/x64/runner/${MODE^}/"* "$dest/"
    echo "[Windows] 完成 → $dest"
}

# Android 构建
build_android() {
    local mode="$1"
    echo "[Android] 构建 $mode 版本..."
    flutter build apk --"$mode"

    local dest="$BUILD_APPS_DIR/${MODE^}/android"
    mkdir -p "$dest"
    cp "build/app/outputs/flutter-apk/app-${mode}.apk" "$dest/"
    echo "[Android] 完成 → $dest/app-${mode}.apk"
}

# Linux 构建
build_linux() {
    echo "[Linux] 构建 release 版本..."
    flutter build linux --release

    local bundle="build/linux/x64/release/bundle"

    # 准备 AppDir
    local appdir="$PROJECT_ROOT/CloudAudiobook.AppDir"
    rm -rf "$appdir"
    mkdir -p "$appdir/usr/bin/data" "$appdir/usr/bin/lib"

    cp "$bundle/cloud_audiobook" "$appdir/usr/bin/"
    cp -r "$bundle/data/"* "$appdir/usr/bin/data/"
    cp "$bundle/lib/"*.so "$appdir/usr/bin/lib/"

    # 打包 libmpv（如果存在）
    [ -f /lib64/libmpv.so.2 ] && cp /lib64/libmpv.so.2 "$appdir/usr/bin/lib/" || true
    [ -f /usr/lib/x86_64-linux-gnu/libmpv.so.2 ] && cp /usr/lib/x86_64-linux-gnu/libmpv.so.2 "$appdir/usr/bin/lib/" || true

    # 创建 AppRun
    printf '#!/bin/bash\nHERE="$(dirname "$(readlink -f "$0")")"\nexport LC_ALL=C\nexport LD_LIBRARY_PATH="$HERE/usr/bin/lib:$LD_LIBRARY_PATH"\ncd "$HERE/usr/bin"\nexec ./cloud_audiobook "$@"\n' > "$appdir/AppRun"
    chmod +x "$appdir/AppRun"

    # 创建 desktop 文件
    cat > "$appdir/cloud-audiobook.desktop" << 'DESKTOP'
[Desktop Entry]
Name=云听书
Exec=cloud_audiobook
Icon=cloud-audiobook
Type=Application
Categories=AudioVideo;Player;
DESKTOP
    touch "$appdir/cloud-audiobook.png"

    # 打包 AppImage
    local appimage_tool="$PROJECT_ROOT/appimagetool-x86_64.AppImage"
    if [ ! -f "$appimage_tool" ]; then
        echo "[Linux] 下载 appimagetool..."
        wget -q https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage -O "$appimage_tool"
        chmod +x "$appimage_tool"
    fi

    local output="cloud-audiobook-v1.0.3-x86_64.AppImage"
    rm -f "$output"
    ARCH=x86_64 "$appimage_tool" "$appdir" "$output"

    local dest="$BUILD_APPS_DIR/${MODE^}/linux"
    mkdir -p "$dest"
    cp "$output" "$dest/"
    echo "[Linux] 完成 → $dest/$output"
}

# 获取版本号
get_version() {
    grep "^version:" pubspec.yaml | sed 's/version: //'
}

VERSION=$(get_version)

# 执行构建
case "$PLATFORM" in
    windows)
        get_deps
        build_windows "$MODE"
        ;;
    android)
        get_deps
        build_android "$MODE"
        ;;
    linux)
        get_deps
        build_linux
        ;;
    all)
        get_deps
        build_windows "$MODE"
        build_android "$MODE"
        # Linux 仅在 Linux 系统上构建
        [ "$(uname -s)" = "Linux" ] && build_linux || echo "[跳过] Linux 构建需要 Linux 环境"
        ;;
    *)
        echo "用法: $0 [windows|android|linux|all] [debug|profile|release]"
        exit 1
        ;;
esac

echo ""
echo "========================================"
echo "  构建完成! 版本: $VERSION"
echo "  产物目录: $BUILD_APPS_DIR"
echo "========================================"
ls -la "$BUILD_APPS_DIR/" 2>/dev/null || echo "(产物目录为空)"
