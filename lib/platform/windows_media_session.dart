import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_media_session/flutter_media_session.dart';
import 'package:flutter_media_session/flutter_media_session_platform_interface.dart';

typedef WindowsMediaCommand = Future<void> Function();

class WindowsMediaSession {
  static final WindowsMediaSession _instance = WindowsMediaSession._();
  factory WindowsMediaSession() => _instance;
  WindowsMediaSession._();

  final _session = FlutterMediaSession();
  bool _active = false;

  Future<void> initialize({
    required WindowsMediaCommand onPlay,
    required WindowsMediaCommand onPause,
    required WindowsMediaCommand onNext,
    required WindowsMediaCommand onPrevious,
    required WindowsMediaCommand onStop,
    required Future<void> Function(Duration position) onSeek,
  }) async {
    if (!Platform.isWindows || _active) return;
    try {
      await _session.activate();
      _session.setActionHandler(
        onPlay: () => unawaited(onPlay()),
        onPause: () => unawaited(onPause()),
        onSkipToNext: () => unawaited(onNext()),
        onSkipToPrevious: () => unawaited(onPrevious()),
        onStop: () => unawaited(onStop()),
        onSeekTo: (position) => unawaited(onSeek(position)),
      );
      _active = true;
    } catch (_) {
      _active = false;
    }
  }

  Future<void> updateMetadata({
    required String title,
    required String artist,
    required Duration duration,
  }) async {
    if (!_active) return;
    await _sessionPlatformUpdateMetadata(
      MediaMetadata(title: title, artist: artist, duration: duration),
    );
  }

  Future<void> updatePlaybackState({
    required bool playing,
    required Duration position,
  }) async {
    if (!_active) return;
    await _sessionPlatformUpdateState(
      PlaybackState(
        status: playing ? PlaybackStatus.playing : PlaybackStatus.paused,
        position: position,
      ),
    );
  }

  Future<void> _sessionPlatformUpdateMetadata(MediaMetadata metadata) {
    return FlutterMediaSessionPlatform.instance.updateMetadata(metadata);
  }

  Future<void> _sessionPlatformUpdateState(PlaybackState state) {
    return FlutterMediaSessionPlatform.instance.updatePlaybackState(state);
  }

  Future<void> dispose() async {
    if (!_active) return;
    _session.clearActionHandler();
    await _session.deactivate();
    _active = false;
  }
}
