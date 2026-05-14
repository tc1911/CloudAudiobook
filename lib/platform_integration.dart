import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class PlatformIntegration {
  Future<void> init() async {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) return;

    await windowManager.ensureInitialized();

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

  /// Update window title with current track info
  void updateTitle(String title) {
    windowManager.setTitle(title.isEmpty ? '云听书' : '云听书 - $title');
  }

  void dispose() {}
}
