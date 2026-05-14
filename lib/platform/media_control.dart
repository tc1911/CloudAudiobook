import 'dart:io' show Platform, File;
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';

/// Platform media control bridge (Android MediaSession)
class MediaControl {
  static const _channel = MethodChannel('com.cloudaudiobook/media');
  static final MediaControl _instance = MediaControl._();
  factory MediaControl() => _instance;
  MediaControl._() {
    if (Platform.isAndroid) {
      _channel.setMethodCallHandler(_handleCall);
    }
  }

  void Function()? onPlay;
  void Function()? onPause;
  void Function()? onNext;
  void Function()? onPrev;

  String? _cachedCoverPath;

  Future<void> updateMetadata({
    required String title,
    String artist = '',
    String? coverPath,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      String? localCover = await _cacheCover(coverPath, title);
      await _channel.invokeMethod('updateMetadata', {
        'title': title,
        'artist': artist,
        'coverPath': localCover,
      });
    } catch (e) {
      debugPrint('[MediaControl] metadata error: $e');
    }
  }

  Future<void> updatePlaybackState({
    required bool playing,
    int positionMs = 0,
    int durationMs = 0,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('updatePlaybackState', {
        'playing': playing,
        'position': positionMs,
        'duration': durationMs,
      });
    } catch (e) {
      debugPrint('[MediaControl] state error: $e');
    }
  }

  Future<String?> _cacheCover(String? remotePath, String title) async {
    if (remotePath == null) return null;
    try {
      if (_cachedCoverPath != null && File(_cachedCoverPath!).existsSync()) {
        return _cachedCoverPath;
      }
      final src = File(remotePath);
      if (!src.existsSync()) return null;
      final dir = await getTemporaryDirectory();
      final safeName = title.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
      final dest = File('${dir.path}/cover_$safeName.jpg');
      if (!dest.existsSync()) {
        await src.copy(dest.path);
      }
      _cachedCoverPath = dest.path;
      return dest.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> _handleCall(MethodCall call) async {
    switch (call.method) {
      case 'onPlay':
        onPlay?.call();
      case 'onPause':
        onPause?.call();
      case 'onNext':
        onNext?.call();
      case 'onPrev':
        onPrev?.call();
    }
  }
}
