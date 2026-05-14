import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kReleaseMode, kProfileMode;
import '../source.dart';
import '../book_db.dart';
import '../sync.dart';
import 'sync_config.dart';

const buildModeName = kReleaseMode ? 'Release' : (kProfileMode ? 'Profile' : 'Debug');

class SettingsScreen extends StatelessWidget {
  final SourceManager sourceManager;
  final BookDatabase bookDb;
  final SyncManager syncManager;

  const SettingsScreen({
    super.key,
    required this.sourceManager,
    required this.bookDb,
    required this.syncManager,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置'), centerTitle: true),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.sync_rounded),
            title: const Text('数据同步'),
            subtitle: const Text('通过 WebDAV 同步书架和进度'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SyncConfigScreen(
                    sourceManager: sourceManager,
                    bookDb: bookDb,
                    syncManager: syncManager,
                  ),
                ),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于云听书'),
            subtitle: const Text('全平台私人有声书库'),
          ),
          ListTile(
            leading: const Icon(Icons.tag),
            title: const Text('版本'),
            subtitle: Text('${buildModeName} v1.0.1 (build 2)'),
          ),
        ],
      ),
    );
  }
}
