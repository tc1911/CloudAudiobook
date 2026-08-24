import 'package:flutter/material.dart';
import '../book_db.dart';
import '../source.dart';
import '../app.dart' show PlayerScreenState;
import '../metadata.dart';
import 'book_detail.dart';
import 'meta_edit.dart';
import 'dart:io' show File;

class BookshelfScreen extends StatefulWidget {
  final BookDatabase bookDb;
  final SourceManager sourceManager;
  final PlayerScreenState? playerState;
  const BookshelfScreen({
    super.key,
    required this.bookDb,
    required this.sourceManager,
    this.playerState,
  });

  @override
  State<BookshelfScreen> createState() => _BookshelfScreenState();
}

class _BookshelfScreenState extends State<BookshelfScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _reload();
  }

  Future<void> _reload() async {
    await widget.bookDb.load();
    for (final group in widget.bookDb.bookGroups) {
      final source = widget.sourceManager.sources
          .cast<BookSource?>()
          .firstWhere((s) => s?.name == group.sourceName, orElse: () => null);
      if (source != null) await group.loadRemoteMetadata(source);
    }
    if (mounted) setState(() {});
  }

  /// Play from last position — find the last played file and resume
  Future<void> _resumeGroup(BookGroup group) async {
    // Find the record with most recent play position
    BookRecord? latest;
    for (final r in group.records) {
      if (r.positionMs > 0 &&
          (latest == null || r.lastPlayedAt > latest.lastPlayedAt)) {
        latest = r;
      }
    }
    if (latest == null) return;

    // Find the source
    BookSource? source;
    for (final s in widget.sourceManager.sources) {
      if (s.name == group.sourceName) {
        source = s;
        break;
      }
    }
    if (source == null || widget.playerState == null) return;

    // Browse folder to get all items
    try {
      final allItems = await source.browse(
        group.folderKey.isEmpty ? '/' : group.folderKey,
      );
      final audioItems = allItems.where((i) => !i.isFolder).toList();
      final item = BookItem(name: latest!.title, path: latest.path);
      widget.playerState!.loadFromSource(
        item,
        source,
        allItems: audioItems,
        resumeMs: latest.positionMs,
      );
    } catch (_) {}
  }

  Widget _buildCover(BookGroup group, ColorScheme cs) {
    final coverPath = group.coverPath;
    if (coverPath != null && File(coverPath).existsSync()) {
      return Image.file(
        File(coverPath),
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholderCover(group, cs),
      );
    }
    return _placeholderCover(group, cs);
  }

  Widget _placeholderCover(BookGroup group, ColorScheme cs) {
    final progressRatio = group.totalDurationMs > 0
        ? (group.totalPositionMs / group.totalDurationMs).clamp(0.0, 1.0)
        : 0.0;
    return Container(
      width: 52,
      height: 52,
      color: cs.surfaceContainerHighest,
      child: Icon(
        progressRatio > 0
            ? Icons.play_circle_filled
            : Icons.auto_stories_rounded,
        color: cs.primary,
        size: progressRatio > 0 ? 28 : 24,
      ),
    );
  }

  void _clearHistory() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空历史'),
        content: const Text('确定要清空所有播放历史吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              for (final g in widget.bookDb.history) {
                await widget.bookDb.deleteGroup(g);
              }
              Navigator.pop(ctx);
              setState(() {});
            },
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }

  void _onGroupTap(BookGroup group) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookDetailScreen(
          group: group,
          sourceManager: widget.sourceManager,
          playerState: widget.playerState,
        ),
      ),
    );
    _reload(); // Reload when coming back
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  String _formatDate(int epoch) {
    final d = DateTime.fromMillisecondsSinceEpoch(epoch);
    return '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('书架'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(text: '收藏'),
            Tab(text: '历史'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildGroupList(widget.bookDb.favorites, cs, isHistory: false),
          _buildGroupList(widget.bookDb.history, cs, isHistory: true),
        ],
      ),
    );
  }

  Widget _buildGroupList(
    List<BookGroup> groups,
    ColorScheme cs, {
    required bool isHistory,
  }) {
    if (groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.library_books_outlined,
              size: 64,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text('暂无书目', style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: groups.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final group = groups[i];
        final progressRatio = group.totalDurationMs > 0
            ? (group.totalPositionMs / group.totalDurationMs).clamp(0.0, 1.0)
            : 0.0;

        return ListTile(
          leading: GestureDetector(
            onTap: () => _resumeGroup(group),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: _buildCover(group, cs),
            ),
          ),
          title: Text(
            group.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Author & narrator
              if (group.author.isNotEmpty || group.narrator.isNotEmpty)
                Text(
                  [
                    if (group.author.isNotEmpty) group.author,
                    if (group.narrator.isNotEmpty) '演播: ${group.narrator}',
                  ].join(' · '),
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 4),
              if (group.lastEpisodeName.isNotEmpty)
                Text(
                  group.lastEpisodeName,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              Text(
                '${group.lastEpisodeTime}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          trailing: PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'edit') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MetaEditScreen(
                      group: group,
                      source: widget.sourceManager.sources
                          .cast<BookSource?>()
                          .firstWhere(
                            (s) => s?.name == group.sourceName,
                            orElse: () => null,
                          ),
                    ),
                  ),
                ).then((_) => setState(() {}));
              }
              if (v == 'fav') {
                widget.bookDb.toggleBookFavorite(group.folderKey);
                setState(() {});
              }
              if (v == 'delete') {
                _confirmDeleteGroup(group);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    const Icon(Icons.edit, size: 18),
                    const SizedBox(width: 8),
                    const Text('编辑元数据'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'fav',
                child: Row(
                  children: [
                    Icon(
                      group.favorited ? Icons.star : Icons.star_border,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(group.favorited ? '取消收藏' : '收藏'),
                  ],
                ),
              ),
              if (isHistory)
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      const Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: Colors.red,
                      ),
                      const SizedBox(width: 8),
                      const Text('删除记录', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
            ],
          ),
          onTap: () => _onGroupTap(group),
        );
      },
    );
  }

  void _confirmDeleteGroup(BookGroup group) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除历史'),
        content: Text('确定要删除「${group.title}」的播放记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              await widget.bookDb.deleteGroup(group);
              Navigator.pop(ctx);
              setState(() {});
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
