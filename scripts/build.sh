#!/bin/bash
# CloudAudiobook 构建脚本 v1.0
# 用法: ./scripts/build.sh [windows|android|linux|all] [debug|profile|release]
# 默认: ./scripts/build.sh all release

set -euo pipefail

PLATFORM="${1:-all}"
MODE="${2:-release}"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_APPS_DIR="$PROJECT_ROOT/../app"

cd "$PROJECT_ROOT"

case "$PLATFORM" in
    windows|android|linux|all) ;;
    *) echo "用法: $0 [windows|android|linux|all] [debug|profile|release]" >&2; exit 2 ;;
esac
case "$MODE" in
    debug|profile|release) ;;
    *) echo "用法: $0 [windows|android|linux|all] [debug|profile|release]" >&2; exit 2 ;;
esac

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
    if [ "$MODE" != release ]; then
        echo "[Linux] 打包格式只支持 release 模式" >&2
        exit 2
    fi
    echo "[Linux] 构建 release 版本..."
    flutter build linux --release

    local bundle="build/linux/x64/release/bundle"
    local package_root="$PROJECT_ROOT/build/linux/package-root"
    local package_work="$PROJECT_ROOT/build/linux/package-work"
    local package_name="cloud-audiobook"
    local version="${VERSION_RAW%%+*}"
    local revision="${VERSION_RAW#*+}"
    [ "$revision" = "$VERSION_RAW" ] && revision=""
    local version_suffix=""
    [ -n "$revision" ] && version_suffix="_$revision"
    local dest="$BUILD_APPS_DIR/${MODE^}/linux"

    rm -rf "$package_root" "$package_work"
    mkdir -p "$package_root/usr/bin" "$package_root/usr/lib/$package_name/lib"
    mkdir -p "$package_root/usr/share/applications"
    mkdir -p "$package_root/usr/share/icons/hicolor/512x512/apps"

    # Install the Flutter bundle under /usr/lib and use a wrapper to expose its libraries.
    cp "$bundle/cloud_audiobook" "$package_root/usr/lib/$package_name/"
    cp -r "$bundle/data/." "$package_root/usr/lib/$package_name/data/"
    cp "$bundle/lib/"*.so "$package_root/usr/lib/$package_name/lib/"
    [ -f /lib64/libmpv.so.2 ] && cp /lib64/libmpv.so.2 "$package_root/usr/lib/$package_name/lib/" || true
    [ -f /usr/lib/x86_64-linux-gnu/libmpv.so.2 ] && cp /usr/lib/x86_64-linux-gnu/libmpv.so.2 "$package_root/usr/lib/$package_name/lib/" || true
    chmod +x "$package_root/usr/lib/$package_name/cloud_audiobook"

    cat > "$package_root/usr/bin/cloud-audiobook" << 'LAUNCHER'
#!/bin/sh
HERE="/usr/lib/cloud-audiobook"
export LC_ALL=C
export LD_LIBRARY_PATH="$HERE/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$HERE/cloud_audiobook" "$@"
LAUNCHER
    chmod +x "$package_root/usr/bin/cloud-audiobook"

    cat > "$package_root/usr/share/applications/cloud-audiobook.desktop" << 'DESKTOP'
[Desktop Entry]
Name=云听书
Exec=cloud-audiobook
Icon=cloud-audiobook
Type=Application
Categories=AudioVideo;Player;
DESKTOP
    cp "$PROJECT_ROOT/web/icons/Icon-512.png" \
        "$package_root/usr/share/icons/hicolor/512x512/apps/cloud-audiobook.png"

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
    cp "$PROJECT_ROOT/web/icons/Icon-512.png" "$appdir/cloud-audiobook.png"

    # 打包 AppImage
    local appimage_tool="$PROJECT_ROOT/appimagetool-x86_64.AppImage"
    if [ ! -f "$appimage_tool" ]; then
        echo "[Linux] 下载 appimagetool..."
        wget -q https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage -O "$appimage_tool"
        chmod +x "$appimage_tool"
    fi

    local output="cloud-audiobook-v${version}-x86_64.AppImage"
    rm -f "$output"
    ARCH=x86_64 "$appimage_tool" "$appdir" "$output"

    mkdir -p "$dest"
    cp "$output" "$dest/"
    echo "[Linux] 完成 → $dest/$output"

    # Debian package
    if command -v dpkg-deb >/dev/null 2>&1; then
        local deb_root="$package_work/deb"
        mkdir -p "$deb_root/DEBIAN"
        cp -r "$package_root/." "$deb_root/"
        cat > "$deb_root/DEBIAN/control" << CONTROL
Package: $package_name
Version: $version
Section: sound
Priority: optional
Architecture: amd64
Maintainer: CloudAudiobook
Description: Private audiobook library and player
 CloudAudiobook plays audiobooks from local, WebDAV, and SMB sources.
Depends: libgtk-3-0, libmpv2, libayatana-appindicator3-1
CONTROL
        local deb_output="$dest/${package_name}_${version}${version_suffix}_amd64.deb"
        dpkg-deb --build --root-owner-group "$deb_root" "$deb_output" >/dev/null
        echo "[Linux] Debian 完成 → $deb_output"
    else
        echo "[跳过] 未找到 dpkg-deb，无法生成 .deb"
    fi

    # RPM package
    if command -v rpmbuild >/dev/null 2>&1; then
        local rpm_top="$package_work/rpm"
        mkdir -p "$rpm_top/BUILD" "$rpm_top/RPMS" "$rpm_top/SOURCES" "$rpm_top/SPECS" "$rpm_top/SRPMS"
        cp -r "$package_root" "$rpm_top/source-root"
        cat > "$rpm_top/SPECS/$package_name.spec" << SPEC
Name: $package_name
Version: $version
Release: ${revision:-1}
Summary: Private audiobook library and player
License: MIT
BuildArch: x86_64
Requires: gtk3
Requires: mpv-libs
Requires: libayatana-appindicator-gtk3

%description
CloudAudiobook plays audiobooks from local, WebDAV, and SMB sources.

%prep

%build

%install
rm -rf %{buildroot}
cp -a %{_topdir}/source-root/. %{buildroot}/

%files
/usr/bin/cloud-audiobook
/usr/lib/cloud-audiobook
/usr/share/applications/cloud-audiobook.desktop
/usr/share/icons/hicolor/512x512/apps/cloud-audiobook.png

%changelog
* Mon Aug 24 2026 CloudAudiobook <noreply@localhost> - $version-$revision
- Build package
SPEC
        rpmbuild --define "_topdir $rpm_top" -bb "$rpm_top/SPECS/$package_name.spec" >/dev/null
        cp "$rpm_top/RPMS/x86_64/"*.rpm "$dest/"
        echo "[Linux] RPM 完成 → $dest"
    else
        echo "[跳过] 未找到 rpmbuild，无法生成 .rpm"
    fi

    # Arch Linux package
    if command -v makepkg >/dev/null 2>&1; then
        local arch_work="$package_work/arch"
        mkdir -p "$arch_work"
        cp -r "$package_root" "$arch_work/package-root"
        cat > "$arch_work/PKGBUILD" << PKGBUILD
pkgname=$package_name
pkgver=$version
pkgrel=${revision:-1}
pkgdesc='Private audiobook library and player'
arch=('x86_64')
license=('MIT')
depends=('gtk3' 'mpv' 'libayatana-appindicator')
source=()
sha256sums=()

package() {
  cp -a "\$startdir/package-root/." "\$pkgdir/"
}
PKGBUILD
        (cd "$arch_work" && makepkg --force --nodeps >/dev/null)
        cp "$arch_work/${package_name}-${version}-${revision:-1}-"*.pkg.tar.zst "$dest/"
        echo "[Linux] Arch 完成 → $dest"
    else
        echo "[跳过] 未找到 makepkg，无法生成 .pkg.tar.zst"
    fi
}

# 获取版本号
get_version() {
    grep "^version:" pubspec.yaml | sed 's/version: //'
}

VERSION=$(get_version)
VERSION_RAW="$VERSION"

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
