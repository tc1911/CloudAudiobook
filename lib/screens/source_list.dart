import 'package:flutter/material.dart';
import '../source.dart';
import 'source_edit.dart';
import 'source_browse.dart';

class SourceSelection {
  final int sourceIndex;
  final BookItem item;
  SourceSelection({required this.sourceIndex, required this.item});
}

class SourceListScreen extends StatefulWidget {
  final SourceManager manager;
  final void Function(
    BookItem item,
    BookSource source,
    List<BookItem> folderItems,
  )?
  onFileSelected;
  const SourceListScreen({
    super.key,
    required this.manager,
    this.onFileSelected,
  });

  @override
  State<SourceListScreen> createState() => _SourceListScreenState();
}

class _SourceListScreenState extends State<SourceListScreen> {
  @override
  void initState() {
    super.initState();
  }

  Future<void> _addSource() async {
    final config = await Navigator.push<SourceConfig>(
      context,
      MaterialPageRoute(builder: (_) => const SourceEditScreen()),
    );
    if (config == null) return;
    final source = WebdavSource(config);
    await widget.manager.add(source);
    setState(() {});
  }

  Future<void> _editSource(int index) async {
    final source = widget.manager.sources[index];
    final config = await Navigator.push<SourceConfig>(
      context,
      MaterialPageRoute(
        builder: (_) => SourceEditScreen(existing: source.config),
      ),
    );
    if (config == null) return;
    source.config.name = config.name;
    source.config.host = config.host;
    source.config.username = config.username;
    source.config.password = config.password;
    await widget.manager.save();
    setState(() {});
  }

  void _removeSource(int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除书源'),
        content: Text('确定要删除「${widget.manager.sources[index].name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              await widget.manager.remove(index);
              Navigator.pop(ctx);
              setState(() {});
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  Future<void> _browseSource(int index) async {
    final source = widget.manager.sources[index];
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SourceBrowseScreen(source: source)),
    );
    if (result == null) return;
    final item = (result as Map)['item'] as BookItem;
    final folder = (result['folder'] as List<BookItem>?) ?? [item];

    if (widget.onFileSelected != null) {
      widget.onFileSelected!(item, source, folder);
    } else {
      Navigator.pop(context, SourceSelection(sourceIndex: index, item: item));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sources = widget.manager.sources;

    return Scaffold(
      appBar: AppBar(title: const Text('书源管理'), centerTitle: true),
      floatingActionButton: FloatingActionButton(
        heroTag: 'source_add',
        onPressed: _addSource,
        child: const Icon(Icons.add),
      ),
      body: sources.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cloud_off_rounded,
                    size: 64,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '暂无书源',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '点击右下角按钮添加',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            )
          : ListView.separated(
              itemCount: sources.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final s = sources[i];
                return ListTile(
                  leading: Icon(
                    s.icon,
                    color: s.enabled ? cs.primary : cs.onSurfaceVariant,
                  ),
                  title: Text(s.name),
                  subtitle: Text(
                    '${s.type.toUpperCase()} — ${s.config.host}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: s.enabled,
                        onChanged: (_) async {
                          await widget.manager.toggle(i);
                          setState(() {});
                        },
                      ),
                      PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'edit') _editSource(i);
                          if (v == 'delete') _removeSource(i);
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'edit', child: Text('编辑')),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('删除'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  onTap: s.enabled ? () => _browseSource(i) : null,
                );
              },
            ),
    );
  }
}
