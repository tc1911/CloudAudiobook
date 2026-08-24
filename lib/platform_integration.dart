import 'dart:async';
import 'dart:io' show Directory, File, Platform, exit;
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

typedef DesktopCommand = Future<void> Function();

class PlatformIntegration with WindowListener, TrayListener {
  DesktopCommand? _onPlay;
  DesktopCommand? _onPause;
  DesktopCommand? _onNext;
  DesktopCommand? _onPrevious;
  DesktopCommand? _onExit;
  bool _playing = false;
  bool _canGoNext = false;
  bool _canGoPrevious = false;
  bool _closeToTray = true;
  bool _exiting = false;

  Future<void> init({
    required DesktopCommand onPlay,
    required DesktopCommand onPause,
    required DesktopCommand onNext,
    required DesktopCommand onPrevious,
    required DesktopCommand onExit,
  }) async {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) return;

    _onPlay = onPlay;
    _onPause = onPause;
    _onNext = onNext;
    _onPrevious = onPrevious;
    _onExit = onExit;
    final prefs = await SharedPreferences.getInstance();
    _closeToTray = prefs.getBool('cloud_audiobook_close_to_tray') ?? true;

    await windowManager.ensureInitialized();
    trayManager.addListener(this);

    final iconPath = _trayIconPath();
    if (iconPath != null) {
      await trayManager.setIcon(iconPath);
    } else {
      debugPrint('[Tray] icon not found; tray may be unavailable');
    }
    if (!Platform.isLinux) {
      await trayManager.setToolTip('云听书');
    }
    await _updateTrayMenu();
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);

    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        title: '云听书',
        size: Size(900, 700),
        minimumSize: Size(400, 500),
        center: true,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }

  String? _trayIconPath() {
    final executableDir = p.dirname(Platform.resolvedExecutable);
    final candidates = Platform.isWindows
        ? [
            p.join(
              executableDir,
              'data',
              'flutter_assets',
              'assets',
              'windows',
              'runner',
              'resources',
              'app_icon.ico',
            ),
            p.join(
              Directory.current.path,
              'windows',
              'runner',
              'resources',
              'app_icon.ico',
            ),
          ]
        : [
            '/usr/share/icons/hicolor/512x512/apps/cloud-audiobook.png',
            p.join(
              executableDir,
              'data',
              'flutter_assets',
              'assets',
              'web',
              'icons',
              'Icon-512.png',
            ),
            p.join(Directory.current.path, 'web', 'icons', 'Icon-512.png'),
          ];
    for (final path in candidates) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  /// Update window title with current track info
  void updateTitle(String title) {
    windowManager.setTitle(title.isEmpty ? '云听书' : '云听书 - $title');
  }

  Future<void> updatePlaybackState({
    required bool playing,
    required bool canGoNext,
    required bool canGoPrevious,
  }) async {
    _playing = playing;
    _canGoNext = canGoNext;
    _canGoPrevious = canGoPrevious;
    await _updateTrayMenu();
  }

  Future<void> _updateTrayMenu() async {
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show', label: '显示主窗口'),
          MenuItem.separator(),
          MenuItem(key: 'toggle', label: _playing ? '暂停' : '播放'),
          MenuItem(key: 'previous', label: '上一集', disabled: !_canGoPrevious),
          MenuItem(key: 'next', label: '下一集', disabled: !_canGoNext),
          MenuItem.separator(),
          MenuItem.checkbox(
            key: 'close_to_tray',
            label: '关闭窗口时保留在托盘',
            checked: _closeToTray,
          ),
          MenuItem(key: 'exit', label: '退出'),
        ],
      ),
    );
  }

  Future<void> showWindow() async {
    await windowManager.show();
    await windowManager.restore();
    await windowManager.focus();
  }

  @override
  void onWindowClose() {
    if (_exiting) return;
    if (_closeToTray) {
      unawaited(windowManager.hide());
    } else {
      unawaited(_exitApp());
    }
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(showWindow());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        unawaited(showWindow());
      case 'toggle':
        unawaited((_playing ? _onPause : _onPlay)?.call() ?? Future.value());
      case 'previous':
        unawaited(_onPrevious?.call() ?? Future.value());
      case 'next':
        unawaited(_onNext?.call() ?? Future.value());
      case 'close_to_tray':
        _closeToTray = !_closeToTray;
        unawaited(_saveCloseToTray());
        unawaited(_updateTrayMenu());
      case 'exit':
        unawaited(_exitApp());
    }
  }

  Future<void> _saveCloseToTray() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('cloud_audiobook_close_to_tray', _closeToTray);
  }

  Future<void> _exitApp() async {
    if (_exiting) return;
    _exiting = true;
    await _onExit?.call();
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
    exit(0);
  }

  Future<void> dispose() async {
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    await trayManager.destroy();
  }
}
