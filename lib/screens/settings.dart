import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kReleaseMode, kProfileMode;
import 'package:package_info_plus/package_info_plus.dart';
import '../source.dart';
import '../book_db.dart';
import '../sync.dart';
import '../theme_manager.dart';
import 'sync_config.dart';
import 'theme_settings.dart';

const buildModeName = kReleaseMode
    ? 'Release'
    : (kProfileMode ? 'Profile' : 'Debug');

String formatAppVersion(String version, String buildNumber) {
  final build = int.tryParse(buildNumber) ?? 0;
  final suffix = build == 1 ? '' : '-$build';
  return 'v$version$suffix';
}

class SettingsScreen extends StatefulWidget {
  final SourceManager sourceManager;
  final BookDatabase bookDb;
  final SyncManager syncManager;
  final ThemeManager themeManager;

  const SettingsScreen({
    super.key,
    required this.sourceManager,
    required this.bookDb,
    required this.syncManager,
    required this.themeManager,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = 'v1.1.0-0';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _version = formatAppVersion(info.version, info.buildNumber);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置'), centerTitle: true),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('主题'),
            subtitle: const Text('自定义配色方案'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ThemeSettingsScreen(themeManager: widget.themeManager),
                ),
              );
            },
          ),
          const Divider(),
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
                    sourceManager: widget.sourceManager,
                    bookDb: widget.bookDb,
                    syncManager: widget.syncManager,
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
            subtitle: Text('$buildModeName $_version'),
          ),
        ],
      ),
    );
  }
}
