class PlaybackSnapshot {
  final String title;
  final String artist;
  final Duration position;
  final Duration duration;
  final bool playing;
  final bool canGoNext;
  final bool canGoPrevious;

  const PlaybackSnapshot({
    this.title = '',
    this.artist = '',
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.playing = false,
    this.canGoNext = false,
    this.canGoPrevious = false,
  });
}

typedef PlaybackCommand = Future<void> Function();
typedef PlaybackSeek = Future<void> Function(Duration position);

class PlaybackController {
  PlaybackCommand? _play;
  PlaybackCommand? _pause;
  PlaybackCommand? _next;
  PlaybackCommand? _previous;
  PlaybackSeek? _seek;

  PlaybackSnapshot snapshot = const PlaybackSnapshot();

  void bind({
    required PlaybackCommand play,
    required PlaybackCommand pause,
    required PlaybackCommand next,
    required PlaybackCommand previous,
    required PlaybackSeek seek,
  }) {
    _play = play;
    _pause = pause;
    _next = next;
    _previous = previous;
    _seek = seek;
  }

  Future<void> play() => _play?.call() ?? Future.value();
  Future<void> pause() => _pause?.call() ?? Future.value();
  Future<void> next() => _next?.call() ?? Future.value();
  Future<void> previous() => _previous?.call() ?? Future.value();
  Future<void> seek(Duration position) =>
      _seek?.call(position) ?? Future.value();

  void update(PlaybackSnapshot value) {
    snapshot = value;
  }

  void clear() {
    _play = null;
    _pause = null;
    _next = null;
    _previous = null;
    _seek = null;
    snapshot = const PlaybackSnapshot();
  }
}
