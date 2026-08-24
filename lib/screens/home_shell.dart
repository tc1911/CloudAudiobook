import 'package:flutter/material.dart';
import '../app.dart' show AudiobookCore, PlayerScreen, PlayerScreenState;
import '../source.dart';
import '../book_db.dart' show BookDatabase, BookGroup;
import '../sync.dart';
import '../theme_manager.dart';
import '../platform_integration.dart';
import '../platform/media_control.dart';
import '../platform/linux_mpris.dart';
import 'source_list.dart';
import 'bookshelf.dart';
import 'settings.dart';

class HomeShell extends StatefulWidget {
  final SourceManager sourceManager;
  final BookDatabase bookDb;
  final ThemeManager themeManager;
  const HomeShell({
    super.key,
    required this.sourceManager,
    required this.bookDb,
    required this.themeManager,
  });

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tabIndex = 1; // start at player
  final AudiobookCore _core = AudiobookCore();
  final GlobalKey<PlayerScreenState> _playerKey = GlobalKey();
  final SyncManager _syncManager = SyncManager();
  final PlatformIntegration _platformIntegration = PlatformIntegration();

  @override
  void initState() {
    super.initState();
    _syncManager.bind(widget.sourceManager, widget.bookDb);
    BookGroup.bindDb(widget.bookDb);
    _initMediaControl();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoResume();
      _autoSync();
      _platformIntegration.init();
      LinuxMpris().initialize(
        onPlay: () async => _playerKey.currentState?.forcePlay(),
        onPause: () async => _playerKey.currentState?.forcePause(),
        onNext: () async => _playerKey.currentState?.callPlayNext?.call(),
        onPrevious: () async => _playerKey.currentState?.callPlayPrev?.call(),
      );
    });
  }

  void _initMediaControl() {
    final mc = MediaControl();
    mc.onPlay = () {
      _playerKey.currentState?.forcePlay();
    };
    mc.onPause = () {
      _playerKey.currentState?.forcePause();
    };
    mc.onToggle = () {
      _playerKey.currentState?.togglePlay();
    };
    mc.onNext = () {
      _playerKey.currentState?.callPlayNext?.call();
    };
    mc.onPrev = () {
      _playerKey.currentState?.callPlayPrev?.call();
    };
  }

  Future<void> _autoSync() async {
    await _syncManager.autoDownloadOnLaunch();
    _syncManager.startAutoIfNeeded();
  }

  @override
  void dispose() {
    _platformIntegration.dispose();
    LinuxMpris().dispose();
    _core.dispose();
    _syncManager.dispose();
    super.dispose();
  }

  /// Auto-resume last played file on startup
  Future<void> _autoResume() async {
    final last = widget.bookDb.history.isNotEmpty
        ? widget.bookDb.history.first
        : null;
    if (last == null) return;

    final lastRec = last.lastPlayedRecord;
    if (lastRec == null || lastRec.positionMs <= 0) return;

    // Find source
    BookSource? source;
    for (final s in widget.sourceManager.sources) {
      if (s.name == last.sourceName) {
        source = s;
        break;
      }
    }
    if (source == null) return;

    // Browse folder for full playlist
    try {
      final allItems = await source.browse(
        last.folderKey.isEmpty ? '/' : last.folderKey,
      );
      final audioItems = allItems.where((i) => !i.isFolder).toList();
      final item = BookItem(name: lastRec.title, path: lastRec.path);
      _playerKey.currentState?.loadFromSource(
        item,
        source,
        allItems: audioItems,
        resumeMs: lastRec.positionMs,
        autoPlay: false,
      );
    } catch (_) {}
  }

  void _switchToTab(int index) {
    setState(() => _tabIndex = index);
  }

  void _onFileSelected(
    BookItem item,
    BookSource source,
    List<BookItem> folderItems,
  ) {
    _playerKey.currentState?.loadFromSource(
      item,
      source,
      allItems: folderItems,
    );
    setState(() => _tabIndex = 1);
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 600;

    if (isWide) {
      return _buildDesktopLayout();
    }
    return _buildMobileLayout();
  }

  // ── Desktop: sidebar navigation ──

  Widget _buildDesktopLayout() {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          NavigationRail(
            selectedIndex: _tabIndex,
            onDestinationSelected: _switchToTab,
            labelType: NavigationRailLabelType.all,
            backgroundColor: cs.surfaceContainerLow,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.dns_rounded),
                label: Text('书源'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.play_circle_rounded),
                label: Text('播放'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.library_books_rounded),
                label: Text('书架'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_rounded),
                label: Text('设置'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          // Content
          Expanded(child: _buildTabContent()),
        ],
      ),
    );
  }

  // ── Mobile: bottom navigation ──

  Widget _buildMobileLayout() {
    return Scaffold(
      body: _buildTabContent(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: _switchToTab,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dns_rounded), label: '书源'),
          NavigationDestination(
            icon: Icon(Icons.play_circle_rounded),
            label: '播放',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_books_rounded),
            label: '书架',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_rounded),
            label: '设置',
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    return IndexedStack(
      index: _tabIndex,
      children: [
        // Tab 0: Sources
        SourceListScreen(
          manager: widget.sourceManager,
          onFileSelected: _onFileSelected,
        ),
        // Tab 1: Player
        PlayerScreen(
          key: _playerKey,
          initialPositionMs: 0,
          core: _core,
          bookDb: widget.bookDb,
          onTitleUpdate: (title) => _platformIntegration.updateTitle(title),
        ),
        // Tab 2: Bookshelf
        BookshelfScreen(
          key: const ValueKey('bookshelf'),
          bookDb: widget.bookDb,
          sourceManager: widget.sourceManager,
          playerState: _playerKey.currentState,
        ),
        // Tab 3: Settings
        SettingsScreen(
          sourceManager: widget.sourceManager,
          bookDb: widget.bookDb,
          syncManager: _syncManager,
          themeManager: widget.themeManager,
        ),
      ],
    );
  }
}
