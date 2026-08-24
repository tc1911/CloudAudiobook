import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'blob_stub.dart' if (dart.library.html) 'blob_web.dart';
import 'source.dart';
import 'screens/home_shell.dart';
import 'book_db.dart';
import 'theme_manager.dart';
import 'platform/media_control.dart';
import 'platform/linux_mpris.dart';

void initMediaKit() {
  if (!kIsWeb &&
      (Platform.isWindows || Platform.isAndroid || Platform.isLinux)) {
    MediaKit.ensureInitialized();
  }
}

class AudiobookApp extends StatelessWidget {
  final int initialPositionMs;
  final SourceManager sourceManager;
  final BookDatabase bookDb;
  final ThemeManager themeManager;
  const AudiobookApp({
    super.key,
    required this.initialPositionMs,
    required this.sourceManager,
    required this.bookDb,
    required this.themeManager,
  });

  @override
  Widget build(BuildContext context) {
    final tm = themeManager;

    Widget app = MaterialApp(
      title: '云听书',
      debugShowCheckedModeBanner: false,
      theme: tm.lightTheme,
      darkTheme: tm.darkTheme,
      themeMode: ThemeMode.dark,
      home: HomeShell(
        sourceManager: sourceManager,
        bookDb: bookDb,
        themeManager: themeManager,
      ),
    );

    // Wrap with DynamicColorBuilder only when in dynamic mode
    if (Platform.isAndroid && tm.mode == 'dynamic') {
      app = DynamicColorBuilder(
        builder: (lightDynamic, darkDynamic) {
          if (lightDynamic != null && darkDynamic != null) {
            tm.updateDynamicColors(lightDynamic, darkDynamic);
          }
          // Rebuild with updated colors
          return MaterialApp(
            title: '云听书',
            debugShowCheckedModeBanner: false,
            theme: tm.lightTheme,
            darkTheme: tm.darkTheme,
            themeMode: ThemeMode.dark,
            home: HomeShell(
              sourceManager: sourceManager,
              bookDb: bookDb,
              themeManager: themeManager,
            ),
          );
        },
      );
    }

    return app;
  }
}

class AudiobookCore {
  final Player _player = Player();
  SharedPreferences? _prefs;
  String _currentSource = '';
  String _currentTitle = '';
  Timer? _saveTimer;

  bool _isPlaying = false;

  /// Called every 3s with current position and source info
  void Function(String source, String path, int positionMs, int durationMs)?
  onPositionUpdate;

  Duration get position => _player.state.position;
  Duration get duration => _player.state.duration;
  String get currentTitle => _currentTitle;
  bool get isPlaying => _isPlaying;

  Stream<Duration> get positionStream => _player.stream.position;
  Stream<Duration> get durationStream => _player.stream.duration;
  Stream<bool> get playingStream => _player.stream.playing;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  Future<void> loadFile(String filePath) async {
    _currentSource = filePath;
    _currentTitle = filePath.split(RegExp(r'[/\\]')).last;
    final savedMs = _prefs?.getInt('pos_$filePath') ?? 0;

    if (kIsWeb) return;
    await _player.open(Media(filePath));
    if (savedMs > 0) {
      await _player.seek(Duration(milliseconds: savedMs));
    }
    _startAutoSave();
  }

  Future<void> loadUrl(
    String url, {
    String title = '',
    Map<String, String>? headers,
    int skipMs = 0,
    bool autoPlay = true,
  }) async {
    _currentSource = url;
    _currentTitle = title.isNotEmpty ? title : url.split('/').last;
    final spMs = _prefs?.getInt('pos_$url') ?? 0;
    final savedMs = skipMs > 0 ? skipMs : spMs;
    debugPrint('[loadUrl] skipMs=$skipMs spMs=$spMs savedMs=$savedMs url=$url');

    await _player.open(Media(url, httpHeaders: headers ?? {}));
    if (!autoPlay) {
      await _player.pause(); // media_kit auto-plays on open
    }
    if (savedMs > 0) {
      // Wait for duration then seek
      await _player.stream.duration
          .firstWhere((d) => d > Duration.zero)
          .timeout(const Duration(seconds: 10), onTimeout: () => Duration.zero);
      debugPrint(
        '[loadUrl] seeking to ${savedMs}ms, duration=${_player.state.duration}',
      );
      await _player.seek(Duration(milliseconds: savedMs));
      // Wait briefly for position to update
      await Future.delayed(const Duration(milliseconds: 500));
      debugPrint(
        '[loadUrl] after seek position=${_player.state.position.inMilliseconds}ms',
      );
    }
    _startAutoSave();
  }

  Future<void> loadBytes(List<int> bytes, String name) async {
    _currentSource = name;
    _currentTitle = name;
    final savedMs = _prefs?.getInt('pos_$name') ?? 0;
    final url = await createBlobUrl(Uint8List.fromList(bytes));
    await _player.open(Media(url));
    if (savedMs > 0) {
      await _player.seek(Duration(milliseconds: savedMs));
    }
    _startAutoSave();
  }

  void _startAutoSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_currentSource.isNotEmpty) {
        final pos = _player.state.position.inMilliseconds;
        final dur = _player.state.duration.inMilliseconds;
        _prefs?.setInt('pos_$_currentSource', pos);
        onPositionUpdate?.call(_currentSource, _currentTitle, pos, dur);
      }
    });
  }

  Future<void> saveNow() async {
    if (_currentSource.isNotEmpty) {
      await _prefs?.setInt(
        'pos_$_currentSource',
        _player.state.position.inMilliseconds,
      );
    }
  }

  Future<void> play() async {
    await _player.play();
    _isPlaying = true;
  }

  Future<void> pause() async {
    await _player.pause();
    _isPlaying = false;
  }

  Future<void> seek(Duration pos) => _player.seek(pos);

  void dispose() {
    _saveTimer?.cancel();
    saveNow();
    _player.dispose();
  }
}

class PlayerScreen extends StatefulWidget {
  final int initialPositionMs;
  final AudiobookCore? core;
  final dynamic bookDb;
  final void Function(String)? onTitleUpdate;
  final void Function(bool playing, bool canGoNext, bool canGoPrevious)?
  onPlaybackStateChanged;
  const PlayerScreen({
    super.key,
    required this.initialPositionMs,
    this.core,
    this.bookDb,
    this.onTitleUpdate,
    this.onPlaybackStateChanged,
  });

  @override
  State<PlayerScreen> createState() => PlayerScreenState();
}

class PlayerScreenState extends State<PlayerScreen> {
  AudiobookCore get _core => widget.core ?? _fallbackCore;
  final AudiobookCore _fallbackCore = AudiobookCore();
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _sourceLoaded = false;
  String _currentTitle = '';

  Timer? _sleepTimer;
  int? _sleepSecondsLeft;
  static const _sleepOptions = [15, 30, 60]; // seconds, for debug

  @override
  void initState() {
    super.initState();
    _core.init();
    _core.onPositionUpdate = (source, path, posMs, durMs) {
      if (_sourceLoaded && _currentPlaylistPath.isNotEmpty) {
        widget.bookDb?.touch(
          title: _currentTitle.isNotEmpty ? _currentTitle : source,
          path: _currentPlaylistPath,
          sourceName: currentSource?.name ?? '本地文件',
          sourceType: currentSource?.type ?? 'local',
          positionMs: posMs,
          durationMs: durMs,
        );
      }
    };
    _core.positionStream.listen((p) => setState(() => _position = p));
    _core.durationStream.listen((d) => setState(() => _duration = d));
    _core.playingStream.listen((p) {
      setState(() => _isPlaying = p);
      MediaControl().updatePlaybackState(
        playing: p,
        positionMs: _core.position.inMilliseconds,
        durationMs: _core.duration.inMilliseconds,
      );
      LinuxMpris().update(
        title: _currentTitle,
        artist: currentSource?.name ?? '',
        playing: p,
        position: _core.position,
        duration: _core.duration,
        canGoNext: _playlist.length > 1,
        canGoPrevious: _playlist.length > 1,
      );
      widget.onPlaybackStateChanged?.call(
        p,
        _playlist.length > 1,
        _playlist.length > 1,
      );
      // Auto-next when playback completes (player stops and position >= duration)
      if (!p && _playlist.length > 1 && _core.duration > Duration.zero) {
        if (_core.position >=
            _core.duration - const Duration(milliseconds: 500)) {
          _playNext();
        }
      }
    });
  }

  @override
  void dispose() {
    _core.dispose();
    _sleepTimer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h:$mm:$ss';
  }

  Future<void> forcePlay() async {
    if (!_sourceLoaded) return;
    await _core.play();
  }

  Future<void> forcePause() async {
    if (!_sourceLoaded) return;
    await _core.pause();
  }

  Future<void> togglePlay() async {
    await _togglePlay();
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      _core.pause();
    } else {
      if (!_sourceLoaded) {
        _showOpenFileHint();
        return;
      }
      try {
        await _core.play();
      } catch (e) {
        debugPrint('play error: $e');
      }
    }
  }

  void loadFromSource(
    BookItem item,
    BookSource source, {
    List<BookItem>? allItems,
    int? resumeMs,
    bool autoPlay = true,
  }) {
    _playlist = allItems ?? [item];
    _playlistIndex = _playlist.indexWhere((i) => i.path == item.path);
    if (_playlistIndex < 0) _playlistIndex = 0;
    widget.onPlaybackStateChanged?.call(
      _isPlaying,
      _playlist.length > 1,
      _playlist.length > 1,
    );
    _selectSourceItem(item, source, resumeMs: resumeMs, autoPlay: autoPlay);
    // Scroll playlist to current item
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_playlistScrollCtrl.hasClients && _playlistIndex >= 0) {
        _playlistScrollCtrl.animateTo(
          _playlistIndex * 48.0, // approximate item height
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Playlist state
  List<BookItem> _playlist = [];
  int _playlistIndex = 0;
  BookSource? currentSource;
  String _currentPlaylistPath = '';
  String? _coverFilePath;
  final ScrollController _playlistScrollCtrl = ScrollController();

  Future<void> _selectSourceItem(
    BookItem item,
    BookSource source, {
    int? resumeMs,
    bool autoPlay = true,
  }) async {
    debugPrint('[_selectSourceItem] autoPlay=$autoPlay resumeMs=$resumeMs');
    currentSource = source;
    _currentPlaylistPath = item.path;
    final url = await source.getStreamUrl(item.path);
    if (url == null) return;

    _sourceLoaded = true;
    _currentTitle = item.name;
    // Update window title
    widget.onTitleUpdate?.call(item.name);

    // Use explicit resumeMs if given, otherwise look up from BookDatabase
    int savedMs = resumeMs ?? 0;
    if (savedMs == 0 && widget.bookDb != null) {
      final rec = widget.bookDb.findByPath(item.path, source.name);
      if (rec != null) savedMs = rec.positionMs;
    }

    Map<String, String>? headers;
    if (source is WebdavSource) {
      final user = source.config.username;
      final pass = source.config.password;
      if (user.isNotEmpty || pass.isNotEmpty) {
        final creds = base64.encode(utf8.encode('$user:$pass'));
        headers = {'Authorization': 'Basic $creds'};
      }
    }

    await _core.loadUrl(
      url,
      title: item.name,
      headers: headers,
      skipMs: savedMs,
      autoPlay: autoPlay,
    );
    _saveToHistory(item, source);
    // Delay slightly so media is loaded and duration is available
    Future.delayed(const Duration(milliseconds: 500), () {
      MediaControl().updateMetadata(
        title: item.name,
        artist: source.name,
        coverPath: _coverFilePath,
      );
      MediaControl().updatePlaybackState(
        playing: _core.isPlaying,
        positionMs: _core.position.inMilliseconds,
        durationMs: _core.duration.inMilliseconds,
      );
    });
    // Try to find cover from book database
    if (widget.bookDb != null) {
      _coverFilePath = null;
      final folderKey = BookDatabase.folderKey(
        BookRecord(path: item.path, sourceName: source.name, title: item.name),
      );
      for (final group in widget.bookDb!.bookGroups) {
        if (group.folderKey == folderKey) {
          _coverFilePath = group.coverPath;
          break;
        }
      }
    }
    setState(() {});
    LinuxMpris().update(
      title: _currentTitle,
      artist: source.name,
      playing: _core.isPlaying,
      position: _core.position,
      duration: _core.duration,
      canGoNext: _playlist.length > 1,
      canGoPrevious: _playlist.length > 1,
    );
    if (autoPlay) _core.play();
  }

  void _saveToHistory(BookItem item, BookSource source) {
    if (widget.bookDb == null) return;
    widget.bookDb.touch(
      title: item.name,
      path: item.path,
      sourceName: source.name,
      sourceType: source.type,
      positionMs: _core.position.inMilliseconds,
      durationMs: _core.duration.inMilliseconds,
    );
  }

  void _showOpenFileHint() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('请先点击右上角文件夹图标选择音频文件'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'mp3',
        'm4a',
        'wav',
        'flac',
        'opus',
        'ogg',
        'aac',
        'wma',
        'aiff',
      ],
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;

    _sourceLoaded = true;
    if (kIsWeb && file.bytes != null) {
      _currentTitle = file.name;
      await _core.loadBytes(file.bytes!, file.name);
    } else if (file.path != null) {
      await _core.loadFile(file.path!);
      _currentTitle = _core.currentTitle;
      // Save to history
      if (widget.bookDb != null) {
        widget.bookDb.touch(
          title: _currentTitle,
          path: file.path!,
          sourceName: '本地文件',
          sourceType: 'local',
        );
      }
    } else {
      return;
    }
    setState(() {});
    _core.play();
  }

  VoidCallback? get callPlayNext => _playlist.length > 1 ? _playNext : null;
  VoidCallback? get callPlayPrev => _playlist.length > 1 ? _playPrev : null;

  void _playNext() {
    if (_playlist.isEmpty) return;
    final next = (_playlistIndex + 1) % _playlist.length;
    if (next == _playlistIndex) return;
    setState(() => _playlistIndex = next);
    if (currentSource != null) {
      _selectSourceItem(_playlist[next], currentSource!);
    }
  }

  void _playPrev() {
    if (_playlist.isEmpty) return;
    final prev = (_playlistIndex - 1).clamp(0, _playlist.length - 1);
    if (prev == _playlistIndex) return;
    setState(() => _playlistIndex = prev);
    if (currentSource != null) {
      _selectSourceItem(_playlist[prev], currentSource!);
    }
  }

  void _setSleepTimer(int seconds) {
    _sleepTimer?.cancel();
    _sleepSecondsLeft = seconds;
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _sleepSecondsLeft = _sleepSecondsLeft! - 1;
      setState(() {});
      if (_sleepSecondsLeft == 0) {
        timer.cancel();
        _sleepSecondsLeft = null;
        _core.pause();
        setState(() {});
      }
    });
    setState(() {});
  }

  void _cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepSecondsLeft = null;
    setState(() {});
  }

  void _showCustomTimerDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('自定义定时'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '分钟',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final minutes = int.tryParse(ctrl.text);
              if (minutes != null && minutes > 0) {
                _setSleepTimer(minutes * 60);
              }
              Navigator.pop(ctx);
            },
            child: const Text('开始'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ts = Theme.of(context).textTheme;
    final isWide = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      appBar: AppBar(
        title: const Text('云听书'),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _openFile,
            icon: const Icon(Icons.folder_open_rounded),
            tooltip: '打开音频文件',
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (_, constraints) {
            final maxWidth = constraints.maxWidth;
            final compact = maxWidth < 600;
            final coverSize = compact ? 200.0 : 160.0;

            return Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Album art — use cover from metadata if available
                          Container(
                            width: coverSize,
                            height: coverSize,
                            margin: const EdgeInsets.only(bottom: 24),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              color: cs.surfaceContainerHighest,
                              boxShadow: [
                                BoxShadow(
                                  color: cs.shadow.withValues(alpha: 0.3),
                                  blurRadius: 24,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                              image: _coverFilePath != null
                                  ? DecorationImage(
                                      image: FileImage(File(_coverFilePath!)),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: _coverFilePath == null
                                ? Icon(
                                    Icons.library_music_rounded,
                                    size: coverSize * 0.4,
                                    color: cs.onSurfaceVariant.withValues(
                                      alpha: 0.6,
                                    ),
                                  )
                                : null,
                          ),
                          // Book title
                          Text(
                            _sourceLoaded ? _currentTitle : '云听书',
                            style: ts.titleLarge,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _sourceLoaded ? '本地文件' : '点右上角文件夹图标选择音频',
                            style: ts.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          // Time labels
                          const SizedBox(height: 24),
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: isWide ? 80 : 0,
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _formatDuration(_position),
                                      style: ts.labelMedium?.copyWith(
                                        color: cs.primary,
                                      ),
                                    ),
                                    Text(
                                      _formatDuration(_duration),
                                      style: ts.labelMedium?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                                SliderTheme(
                                  data: SliderThemeData(
                                    trackHeight: 4,
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 8,
                                    ),
                                    activeTrackColor: cs.primary,
                                    inactiveTrackColor:
                                        cs.surfaceContainerHighest,
                                    thumbColor: cs.primary,
                                  ),
                                  child: Slider(
                                    value: _duration.inMilliseconds > 0
                                        ? _position.inMilliseconds
                                              .toDouble()
                                              .clamp(
                                                0,
                                                _duration.inMilliseconds
                                                    .toDouble(),
                                              )
                                        : 0,
                                    max: _duration.inMilliseconds > 0
                                        ? _duration.inMilliseconds.toDouble()
                                        : 1.0,
                                    onChanged: (v) {
                                      _core.seek(
                                        Duration(milliseconds: v.toInt()),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Controls
                          const SizedBox(height: 16),
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: compact ? 8 : (isWide ? 160 : 32),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Prev episode
                                IconButton.filledTonal(
                                  onPressed: _playlist.length > 1
                                      ? _playPrev
                                      : null,
                                  icon: const Icon(Icons.skip_previous_rounded),
                                  iconSize: compact ? 22 : 28,
                                  tooltip: '上一集',
                                  visualDensity: VisualDensity.compact,
                                ),
                                SizedBox(width: compact ? 8 : 16),
                                FloatingActionButton(
                                  heroTag: 'player_play',
                                  onPressed: _togglePlay,
                                  elevation: 4,
                                  child: Icon(
                                    _isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    size: compact ? 32 : 40,
                                  ),
                                ),
                                SizedBox(width: compact ? 8 : 16),
                                // Next episode
                                IconButton.filledTonal(
                                  onPressed: _playlist.length > 1
                                      ? _playNext
                                      : null,
                                  icon: const Icon(Icons.skip_next_rounded),
                                  iconSize: compact ? 22 : 28,
                                  tooltip: '下一集',
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                          ),
                          // Sleep timer
                          const SizedBox(height: 24),
                          _sleepSecondsLeft != null
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.timer,
                                      color: cs.primary,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${(_sleepSecondsLeft! ~/ 60).toString().padLeft(2, '0')}:${(_sleepSecondsLeft! % 60).toString().padLeft(2, '0')}',
                                      style: ts.titleSmall?.copyWith(
                                        color: cs.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    TextButton(
                                      onPressed: _cancelSleepTimer,
                                      child: const Text('取消'),
                                    ),
                                  ],
                                )
                              : Wrap(
                                  alignment: WrapAlignment.center,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 8,
                                  children: [
                                    Icon(
                                      Icons.timer_outlined,
                                      color: cs.onSurfaceVariant,
                                      size: 20,
                                    ),
                                    ..._sleepOptions.map(
                                      (s) => ActionChip(
                                        label: Text('${s}s'),
                                        onPressed: () => _setSleepTimer(s),
                                      ),
                                    ),
                                    ActionChip(
                                      avatar: const Icon(
                                        Icons.more_time,
                                        size: 18,
                                      ),
                                      label: const Text('自定义'),
                                      onPressed: _showCustomTimerDialog,
                                    ),
                                  ],
                                ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                ),
                // Playlist OUTSIDE the scroll — uses remaining space
                if (_playlist.length > 1)
                  Container(
                    height: compact ? 140 : 120,
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: cs.outlineVariant.withValues(alpha: 0.3),
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 24, top: 6),
                          child: Text(
                            '播放列表 (${_playlist.length})',
                            style: ts.titleSmall,
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            controller: _playlistScrollCtrl,
                            itemCount: _playlist.length,
                            itemBuilder: (_, i) => ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              leading: Icon(
                                i == _playlistIndex
                                    ? Icons.play_arrow
                                    : Icons.audio_file_rounded,
                                size: 18,
                                color: i == _playlistIndex
                                    ? cs.primary
                                    : cs.onSurfaceVariant,
                              ),
                              title: Text(
                                _playlist[i].name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: i == _playlistIndex
                                      ? cs.primary
                                      : null,
                                ),
                              ),
                              onTap: () {
                                setState(() => _playlistIndex = i);
                                _selectSourceItem(_playlist[i], currentSource!);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
              ],
            ); // Column end
          },
        ),
      ),
    );
  }
}
