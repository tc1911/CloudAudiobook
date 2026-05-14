import 'package:flutter/material.dart';
import '../source.dart';
import '../book_db.dart';
import '../sync.dart';
import 'source_browse.dart';

class SyncConfigScreen extends StatefulWidget {
  final SourceManager sourceManager;
  final BookDatabase bookDb;
  final SyncManager syncManager;

  const SyncConfigScreen({
    super.key,
    required this.sourceManager,
    required this.bookDb,
    required this.syncManager,
  });

  @override
  State<SyncConfigScreen> createState() => _SyncConfigScreenState();
}

class _SyncConfigScreenState extends State<SyncConfigScreen> {
  String? _syncSourceName;
  String? _syncRemotePath;
  bool _autoUpload = false;
  bool _autoDownload = false;
  bool _syncing = false;
  String? _statusMessage;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await widget.syncManager.loadConfig();
    setState(() {
      _syncSourceName = widget.syncManager.sourceName;
      _syncRemotePath = widget.syncManager.remotePath;
      _autoUpload = widget.syncManager.autoUpload;
      _autoDownload = widget.syncManager.autoDownload;
      _loaded = true;
    });
  }

  List<WebdavSource> get _webdavSources =>
      widget.sourceManager.sources.whereType<WebdavSource>().toList();

  Future<void> _save() async {
    if (_syncSourceName == null || _syncRemotePath == null) return;
    await widget.syncManager.saveConfig(_syncSourceName!, _syncRemotePath!);
  }

  Future<void> _doUpload() async {
    if (_syncSourceName == null || _syncRemotePath == null) {
      setState(() => _statusMessage = '请先配置同步目标');
      return;
    }
    setState(() { _syncing = true; _statusMessage = null; });
    final err = await widget.syncManager.upload(widget.sourceManager, widget.bookDb);
    setState(() { _syncing = false; _statusMessage = err ?? '上传成功'; });
  }

  Future<void> _doDownload() async {
    if (_syncSourceName == null || _syncRemotePath == null) {
      setState(() => _statusMessage = '请先配置同步目标');
      return;
    }
    setState(() { _syncing = true; _statusMessage = null; });
    final err = await widget.syncManager.download(widget.sourceManager, widget.bookDb);
    setState(() { _syncing = false; _statusMessage = err ?? '下载成功'; });
  }

  Future<void> _pickFolder() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String? selected;
        return StatefulBuilder(
          builder: (ctx, setDlg) => AlertDialog(
            title: const Text('选择同步书源'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: _webdavSources.map((s) => RadioListTile<String>(
                    title: Text(s.name),
                    value: s.name,
                    groupValue: selected,
                    onChanged: (v) => setDlg(() => selected = v),
                  )).toList(),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              FilledButton(
                onPressed: selected != null ? () => Navigator.pop(ctx, selected) : null,
                child: const Text('下一步'),
              ),
            ],
          ),
        );
      },
    );
    if (picked == null) return;

    final source = _webdavSources.firstWhere((s) => s.name == picked);
    final item = await Navigator.push<BookItem>(
      context,
      MaterialPageRoute(builder: (_) => SourceBrowseScreen(source: source, selectFolder: true)),
    );
    if (item != null) {
      setState(() {
        _syncSourceName = picked;
        _syncRemotePath = item.path;
      });
      await _save();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(title: const Text('数据同步'), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Sync target card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('同步目标', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    if (_syncSourceName != null && _syncRemotePath != null) ...[
                      Row(
                        children: [
                          const Icon(Icons.cloud_done, color: Colors.green, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_syncSourceName!, style: const TextStyle(fontWeight: FontWeight.bold)),
                                Text('/$_syncRemotePath', style: Theme.of(context).textTheme.bodySmall),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ] else
                      Text('未配置', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _pickFolder,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('选择同步目录'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Auto sync toggles
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('自动备份', style: Theme.of(context).textTheme.titleSmall),
                    SwitchListTile(
                      title: const Text('启动时自动恢复'),
                      subtitle: const Text('每次打开 App 自动下载最新备份'),
                      value: _autoDownload,
                      onChanged: (v) {
                        setState(() => _autoDownload = v);
                        widget.syncManager.setAutoDownload(v);
                      },
                    ),
                    SwitchListTile(
                      title: const Text('定时自动上传'),
                      subtitle: const Text('每 5 分钟自动上传一次'),
                      value: _autoUpload,
                      onChanged: (v) {
                        setState(() => _autoUpload = v);
                        widget.syncManager.setAutoUpload(v);
                        widget.syncManager.startAutoIfNeeded();
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Manual sync
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _syncing ? null : _doUpload,
                    icon: const Icon(Icons.cloud_upload),
                    label: const Text('立即上传'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _syncing ? null : _doDownload,
                    icon: const Icon(Icons.cloud_download),
                    label: const Text('立即下载'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_syncing) const Center(child: CircularProgressIndicator()),
            if (_statusMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  _statusMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _statusMessage!.contains('成功')
                        ? Colors.green
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
