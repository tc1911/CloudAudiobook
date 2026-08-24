import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../book_db.dart';
import '../metadata.dart';
import '../source.dart';

class MetaEditScreen extends StatefulWidget {
  final BookGroup group;
  final BookSource? source;
  const MetaEditScreen({super.key, required this.group, this.source});

  @override
  State<MetaEditScreen> createState() => _MetaEditScreenState();
}

class _MetaEditScreenState extends State<MetaEditScreen> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _authorCtrl;
  late final TextEditingController _narratorCtrl;
  late final TextEditingController _descCtrl;
  String? _coverPath;
  String _coverName = '';

  @override
  void initState() {
    super.initState();
    // Check if meta exists on disk
    final hasMeta = widget.source is WebdavSource
        ? widget.group.meta.title.isNotEmpty
        : widget.group.hasMeta;
    if (!hasMeta) {
      // Schedule prompt after first frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _promptCreate();
      });
    }
    final meta = widget.group.meta;
    _titleCtrl = TextEditingController(text: meta.title);
    _authorCtrl = TextEditingController(text: meta.author);
    _narratorCtrl = TextEditingController(text: meta.narrator);
    _descCtrl = TextEditingController(text: meta.description);
    _coverPath = widget.group.coverPath;
    _coverName = meta.cover;
  }

  void _promptCreate() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('未检测到元数据'),
        content: const Text('该书还没有 .BookInformation 元数据。要自动创建吗？'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx); // close dialog
              if (mounted) Navigator.pop(context); // go back to previous page
            },
            child: const Text('暂不'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final defaultMeta = BookMeta(title: widget.group.title);
              if (widget.source is WebdavSource) {
                await (widget.source! as WebdavSource).writeMetadata(
                  widget.group.folderPath,
                  defaultMeta,
                );
              } else {
                await MetadataManager.createDefault(widget.group.folderPath);
              }
              widget.group.refreshMeta();
              final meta = widget.group.meta;
              setState(() {
                _titleCtrl.text = meta.title;
                _authorCtrl.text = meta.author;
                _narratorCtrl.text = meta.narrator;
                _descCtrl.text = meta.description;
                _coverPath = widget.group.coverPath;
                _coverName = meta.cover;
              });
            },
            child: const Text('自动创建'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _authorCtrl.dispose();
    _narratorCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickCover() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    if (file.path == null) return;

    final ext = file.name.split('.').last;
    if (widget.source is WebdavSource) {
      _coverName = 'cover.$ext';
      await (widget.source! as WebdavSource).writeMetadataCover(
        widget.group.folderPath,
        _coverName,
        await File(file.path!).readAsBytes(),
      );
    } else {
      final metaDir = MetadataManager.metaDir(widget.group.folderPath);
      final dir = Directory(metaDir);
      if (!await dir.exists()) await dir.create(recursive: true);
      final dest = File('$metaDir${Platform.pathSeparator}cover.$ext');
      await File(file.path!).copy(dest.path);
      _coverPath = dest.path;
    }
    widget.group.refreshMeta();
    setState(() {});
  }

  Future<void> _save() async {
    final meta = BookMeta(
      title: _titleCtrl.text.trim(),
      author: _authorCtrl.text.trim(),
      narrator: _narratorCtrl.text.trim(),
      cover: _coverName,
      description: _descCtrl.text.trim(),
    );
    if (widget.source is WebdavSource) {
      await (widget.source! as WebdavSource).writeMetadata(
        widget.group.folderPath,
        meta,
      );
    } else {
      await MetadataManager.write(widget.group.folderPath, meta);
    }
    widget.group.refreshMeta();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑元数据'),
        actions: [IconButton(icon: const Icon(Icons.check), onPressed: _save)],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Cover
            Center(
              child: GestureDetector(
                onTap: _pickCover,
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    image: _coverPath != null
                        ? DecorationImage(
                            image: FileImage(File(_coverPath!)),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: _coverPath == null
                      ? const Icon(Icons.add_photo_alternate, size: 48)
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text('点击更换封面', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: '书名',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _authorCtrl,
              decoration: const InputDecoration(
                labelText: '作者',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _narratorCtrl,
              decoration: const InputDecoration(
                labelText: '演播者',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: '简介',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}
