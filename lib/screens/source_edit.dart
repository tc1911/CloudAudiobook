import 'package:flutter/material.dart';
import '../source.dart';

class SourceEditScreen extends StatefulWidget {
  final SourceConfig? existing;
  const SourceEditScreen({super.key, this.existing});

  @override
  State<SourceEditScreen> createState() => _SourceEditScreenState();
}

class _SourceEditScreenState extends State<SourceEditScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _hostCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;
  String _type = 'webdav';

  final _typeLabels = {
    'webdav': 'WebDAV',
    'smb': 'SMB / 网络共享',
  };

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _hostCtrl = TextEditingController(text: widget.existing?.host ?? '');
    _userCtrl = TextEditingController(text: widget.existing?.username ?? '');
    _passCtrl = TextEditingController(text: widget.existing?.password ?? '');
    _type = widget.existing?.type ?? 'webdav';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    final host = _hostCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('名称不能为空')),
      );
      return;
    }
    if (host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('地址不能为空')),
      );
      return;
    }
    final config = SourceConfig(
      id: widget.existing?.id,
      name: name,
      type: _type,
      host: host,
      username: _userCtrl.text.trim(),
      password: _passCtrl.text.trim(),
      enabled: widget.existing?.enabled ?? true,
    );
    Navigator.pop(context, config);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? '编辑书源' : '添加书源'),
        actions: [IconButton(icon: const Icon(Icons.check), onPressed: _save)],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            // Type selector
            DropdownButtonFormField<String>(
              value: _type,
              decoration: const InputDecoration(
                labelText: '类型',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: _typeLabels.entries
                  .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) => setState(() => _type = v ?? 'webdav'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: '名称',
                hintText: _type == 'smb' ? '如：我的 NAS' : '如：我的 WebDAV',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.label_outline),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _hostCtrl,
              decoration: InputDecoration(
                labelText: _type == 'smb' ? '网络路径' : '地址',
                hintText: _type == 'smb' ? r'\\192.168.1.100\share 或 Z:\' : 'https://example.com/remote.php/dav/',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.link),
              ),
              keyboardType: _type == 'smb' ? TextInputType.text : TextInputType.url,
            ),
            if (_type == 'aliyun') ...[] else ...[
              const SizedBox(height: 16),
              TextField(
                controller: _userCtrl,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passCtrl,
                decoration: const InputDecoration(
                  labelText: '密码',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                obscureText: true,
              ),
            ],
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save),
                label: Text(isEdit ? '保存修改' : '添加书源'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
