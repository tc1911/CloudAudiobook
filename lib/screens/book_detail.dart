import 'package:flutter/material.dart';
import '../book_db.dart';
import '../source.dart';
import '../app.dart' show PlayerScreenState;

class BookDetailScreen extends StatefulWidget {
  final BookGroup group;
  final SourceManager sourceManager;
  final PlayerScreenState? playerState;

  const BookDetailScreen({
    super.key,
    required this.group,
    required this.sourceManager,
    this.playerState,
  });

  @override
  State<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends State<BookDetailScreen> {
  List<BookItem> _allItems = [];
  bool _loading = true;

  BookSource? get _source =>
      widget.sourceManager.sources.cast<BookSource?>().firstWhere(
        (s) => s?.name == widget.group.sourceName,
        orElse: () => null,
      );

  BookRecord? _findProgress(BookItem item) {
    try {
      return widget.group.records.firstWhere((r) => r.path == item.path);
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadFolder();
  }

  Future<void> _loadFolder() async {
    final source = _source;
    if (source == null) {
      setState(() => _loading = false);
      return;
    }
    await widget.group.loadRemoteMetadata(source);
    try {
      // Get all items in the folder key path
      final folderKey = widget.group.folderKey;
      final allItems = await source.browse(folderKey.isEmpty ? '/' : folderKey);
      // Filter to audio files only, sort naturally
      final audioItems = allItems.where((i) => !i.isFolder).toList()
        ..sort((a, b) => _naturalSort(a.name, b.name));
      setState(() {
        _allItems = audioItems;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _allItems = [];
        _loading = false;
      });
    }
  }

  void _play(BookItem item) {
    final source = _source;
    if (source == null || widget.playerState == null) return;
    widget.playerState!.loadFromSource(item, source, allItems: _allItems);
    Navigator.pop(context);
  }

  String _formatMs(int ms) {
    final m = ms ~/ 60000;
    final s = (ms ~/ 1000) % 60;
    return '${m}:${s.toString().padLeft(2, '0')}';
  }

  int _naturalSort(String a, String b) {
    final aLower = a.toLowerCase();
    final bLower = b.toLowerCase();
    final aParts = RegExp(r'(\d+|\D+)').allMatches(aLower).toList();
    final bParts = RegExp(r'(\d+|\D+)').allMatches(bLower).toList();
    for (var i = 0; i < aParts.length && i < bParts.length; i++) {
      final aStr = aParts[i].group(0)!;
      final bStr = bParts[i].group(0)!;
      final aNum = int.tryParse(aStr);
      final bNum = int.tryParse(bStr);
      if (aNum != null && bNum != null) {
        if (aNum != bNum) return aNum.compareTo(bNum);
      } else {
        final cmp = aStr.compareTo(bStr);
        if (cmp != 0) return cmp;
      }
    }
    return aParts.length.compareTo(bParts.length);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(widget.group.title), centerTitle: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _allItems.isEmpty
          ? Center(
              child: Text(
                '无法加载目录',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            )
          : ListView.separated(
              itemCount: _allItems.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final item = _allItems[i];
                final rec = _findProgress(item);
                final posMs = rec?.positionMs ?? 0;
                final durMs = rec?.durationMs ?? 0;
                final isFinished = durMs > 0 && posMs >= durMs - 10000;
                final inProgress = posMs > 0 && !isFinished;

                return ListTile(
                  leading: Icon(
                    inProgress
                        ? Icons.play_circle_filled
                        : isFinished
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: inProgress
                        ? cs.primary
                        : isFinished
                        ? cs.tertiary
                        : cs.onSurfaceVariant,
                  ),
                  title: Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: inProgress ? cs.primary : null,
                      fontWeight: inProgress
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  subtitle: durMs > 0
                      ? Text('${_formatMs(posMs)} / ${_formatMs(durMs)}')
                      : null,
                  tileColor: inProgress
                      ? cs.primaryContainer.withValues(alpha: 0.15)
                      : null,
                  onTap: () => _play(item),
                );
              },
            ),
    );
  }
}
