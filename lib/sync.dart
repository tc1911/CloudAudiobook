import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'source.dart';
import 'book_db.dart';

class SyncManager {
  static const _syncConfigKey = 'cloud_audiobook_sync_config';

  String? sourceName;
  String? remotePath;
  bool autoUpload = false;
  bool autoDownload = false;

  Timer? _autoTimer;
  SourceManager? _sources;
  BookDatabase? _books;

  bool get configured => sourceName != null && remotePath != null;
  bool get autoEnabled => autoUpload || autoDownload;

  Future<void> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_syncConfigKey);
    if (json == null) return;
    final cfg = jsonDecode(json) as Map<String, dynamic>;
    sourceName = cfg['sourceName'] as String?;
    remotePath = cfg['remotePath'] as String?;
    autoUpload = cfg['autoUpload'] as bool? ?? false;
    autoDownload = cfg['autoDownload'] as bool? ?? false;
  }

  Future<void> saveConfig(String name, String path) async {
    final prefs = await SharedPreferences.getInstance();
    sourceName = name;
    remotePath = path;
    await _saveAll(prefs);
  }

  Future<void> setAutoUpload(bool v) async {
    autoUpload = v;
    await _saveAll(await SharedPreferences.getInstance());
    _restartAutoTimer();
  }

  Future<void> setAutoDownload(bool v) async {
    autoDownload = v;
    await _saveAll(await SharedPreferences.getInstance());
  }

  Future<void> _saveAll(SharedPreferences prefs) async {
    await prefs.setString(
      _syncConfigKey,
      jsonEncode({
        'sourceName': sourceName,
        'remotePath': remotePath,
        'autoUpload': autoUpload,
        'autoDownload': autoDownload,
      }),
    );
  }

  /// Bind to source/book managers for auto operations
  void bind(SourceManager sources, BookDatabase books) {
    _sources = sources;
    _books = books;
  }

  /// Start auto timer (uploads every 5 minutes)
  void _restartAutoTimer() {
    _autoTimer?.cancel();
    if (!autoUpload || _sources == null || _books == null) return;
    _autoTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      upload(_sources!, _books!);
    });
  }

  /// Called on app startup — auto download if enabled
  Future<void> autoDownloadOnLaunch() async {
    await loadConfig();
    if (!autoDownload || !configured || _sources == null || _books == null)
      return;
    debugPrint('[Sync] auto-downloading...');
    await download(_sources!, _books!);
  }

  void startAutoIfNeeded() {
    _restartAutoTimer();
  }

  void dispose() {
    _autoTimer?.cancel();
  }

  // ─── Upload / Download ───

  WebdavSource? _findSource(SourceManager manager) {
    if (sourceName == null) return null;
    for (final s in manager.sources) {
      if (s is WebdavSource && s.name == sourceName) return s;
    }
    return null;
  }

  Future<String?> upload(SourceManager sources, BookDatabase books) async {
    final source = _findSource(sources);
    if (source == null) return '未找到同步目标书源: $sourceName';
    final basePath =
        '/${remotePath?.replaceAll(RegExp(r'^/+|/+$'), '') ?? 'cloudaudiobook'}';
    try {
      // Credentials stay on the device and are never written to the sync target.
      final sourcesJson = jsonEncode(
        sources.sources
            .map((s) => s.config.toJson(includeCredentials: false))
            .toList(),
      );
      await _putFile(source, '$basePath/sources.json', sourcesJson);
      final booksJson = jsonEncode(books.books.map((b) => b.toJson()).toList());
      await _putFile(source, '$basePath/books.json', booksJson);
      debugPrint('[Sync] upload OK');
      return null;
    } catch (e) {
      debugPrint('[Sync] upload error: $e');
      return '同步失败: $e';
    }
  }

  Future<String?> download(SourceManager sources, BookDatabase books) async {
    final source = _findSource(sources);
    if (source == null) return '未找到同步目标书源: $sourceName';
    final basePath =
        '/${remotePath?.replaceAll(RegExp(r'^/+|/+$'), '') ?? 'cloudaudiobook'}';
    try {
      final sourcesBody = await _getFile(source, '$basePath/sources.json');
      if (sourcesBody != null) {
        final remoteSources = (jsonDecode(sourcesBody) as List<dynamic>)
            .map((e) => SourceConfig.fromJson(e as Map<String, dynamic>))
            .toList();
        for (final rs in remoteSources) {
          final exists = sources.sources.any((s) => s.config.id == rs.id);
          if (!exists) await sources.add(sources.createSource(rs));
        }
      }
      final booksBody = await _getFile(source, '$basePath/books.json');
      if (booksBody != null) {
        final remoteBooks = (jsonDecode(booksBody) as List<dynamic>)
            .map((e) => BookRecord.fromJson(e as Map<String, dynamic>))
            .toList();
        for (final rb in remoteBooks) {
          final exists = books.books.any((b) => b.id == rb.id);
          if (!exists) {
            books.books.add(rb);
          } else {
            final existing = books.books.firstWhere((b) => b.id == rb.id);
            if (rb.lastPlayedAt > existing.lastPlayedAt ||
                rb.positionMs > existing.positionMs) {
              existing.positionMs = rb.positionMs;
              existing.durationMs = rb.durationMs;
              existing.lastPlayedAt = rb.lastPlayedAt;
              existing.favorited = rb.favorited;
            }
          }
        }
        await books.save();
      }
      debugPrint('[Sync] download OK');
      return null;
    } catch (e) {
      debugPrint('[Sync] download error: $e');
      return '下载失败: $e';
    }
  }

  Future<void> _putFile(
    WebdavSource source,
    String path,
    String content,
  ) async {
    final url = source.url(path);
    final client = source.httpClient;
    final resp = await client.put(
      Uri.parse(url),
      headers: {
        'Authorization': source.authHeader(),
        'Content-Type': 'application/json',
      },
      body: content,
    );
    if (resp.statusCode >= 400)
      throw Exception('PUT $path: ${resp.statusCode}');
  }

  Future<String?> _getFile(WebdavSource source, String path) async {
    final url = source.url(path);
    final client = source.httpClient;
    final resp = await client.get(
      Uri.parse(url),
      headers: {'Authorization': source.authHeader()},
    );
    if (resp.statusCode == 404) return null;
    if (resp.statusCode >= 400)
      throw Exception('GET $path: ${resp.statusCode}');
    return resp.body;
  }
}
