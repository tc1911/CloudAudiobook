import 'package:flutter/material.dart';
import '../source.dart';

class SourceBrowseScreen extends StatefulWidget {
  final BookSource source;
  final bool selectFolder;
  const SourceBrowseScreen({super.key, required this.source, this.selectFolder = false});

  @override
  State<SourceBrowseScreen> createState() => _SourceBrowseScreenState();
}

class _SourceBrowseScreenState extends State<SourceBrowseScreen> {
  final List<String> _pathStack = [''];
  List<BookItem> _items = [];
  bool _loading = false;
  String? _error;

  String get _currentPath => _pathStack.last;

  @override
  void initState() {
    super.initState();
    _browse('');
  }

  Future<void> _browse(String path) async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final items = await widget.source.browse(path);
      if (!mounted) return;
      setState(() { _items = items; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _enterFolder(BookItem item) {
    _pathStack.add(item.path);
    _browse(item.path);
  }

  void _goBack() {
    if (_pathStack.length > 1) {
      _pathStack.removeLast();
      _browse(_currentPath);
    }
  }

  void _selectFile(BookItem item) {
    // Return selected file + all audio in folder
    final audioItems = _items.where((i) => !i.isFolder).toList();
    Navigator.pop(context, {'item': item, 'folder': audioItems});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.source.name),
        leading: _pathStack.length > 1
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: _goBack)
            : IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        actions: widget.selectFolder
            ? [
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(context, BookItem(
                      name: _pathStack.last.isEmpty ? '/' : _pathStack.last.split('/').last,
                      path: _currentPath,
                      isFolder: true,
                    ));
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('选此目录'),
                ),
              ]
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: cs.error),
                      const SizedBox(height: 8),
                      Text(_error!, style: TextStyle(color: cs.error)),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => _browse(_currentPath),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : _items.isEmpty
                  ? const Center(child: Text('目录为空'))
                  : ListView.separated(
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final item = _items[i];
                        return ListTile(
                          leading: Icon(
                            item.isFolder ? Icons.folder_rounded : Icons.audio_file_rounded,
                            color: item.isFolder ? cs.primary : cs.onSurfaceVariant,
                          ),
                          title: Text(item.name),
                          trailing: item.isFolder ? const Icon(Icons.chevron_right) : null,
                          onTap: () {
                            if (item.isFolder) {
                              _enterFolder(item);
                            } else {
                              _selectFile(item);
                            }
                          },
                        );
                      },
                    ),
    );
  }
}
