import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:xml/xml.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Natural sort: "第2集" before "第10集", handles numbers in filenames
int _naturalCompare(String a, String b) {
  final aLower = a.toLowerCase();
  final bLower = b.toLowerCase();
  // Extract numbers and non-numbers
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

// ─── Data Models ───

class BookItem {
  final String name;
  final String path;
  final bool isFolder;
  BookItem({required this.name, required this.path, this.isFolder = false});
}

class SourceConfig {
  String id;
  String name;
  String type; // webdav, smb, aliyun (aliyun future)
  String host;
  String username;
  String password;
  bool enabled;

  SourceConfig({
    String? id,
    this.name = '',
    this.type = 'webdav',
    this.host = '',
    this.username = '',
    this.password = '',
    this.enabled = true,
  }) : id = id ?? DateTime.now().millisecondsSinceEpoch.toString();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'host': host,
        'username': username,
        'password': password,
        'enabled': enabled,
      };

  factory SourceConfig.fromJson(Map<String, dynamic> json) => SourceConfig(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        type: json['type'] as String? ?? 'webdav',
        host: json['host'] as String? ?? '',
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
        enabled: json['enabled'] as bool? ?? true,
      );
}

// ─── Abstract BookSource ───

abstract class BookSource {
  final SourceConfig config;
  BookSource(this.config);

  String get name => config.name;
  String get type => config.type;
  IconData get icon;
  bool get enabled => config.enabled;

  /// Browse a directory. Return list of [BookItem].
  Future<List<BookItem>> browse(String path);

  /// Get a streamable URL for a file.
  /// Return the URL string, or null if not supported.
  Future<String?> getStreamUrl(String filePath);
}

// ─── WebDAV Implementation ───

class WebdavSource extends BookSource {
  WebdavSource(super.config);

  http.Client? _client;

  http.Client get httpClient {
    _client?.close();
    final io = platformHttpClient();
    final client = IOClient(io);
    _client = client;
    return client;
  }

  // helper to allow self-signed certs
  static HttpClient platformHttpClient() {
    final hc = HttpClient()
      ..badCertificateCallback = (_, __, ___) => true;
    return hc;
  }

  String authHeader() {
    final creds = base64.encode(utf8.encode('${config.username}:${config.password}'));
    return 'Basic $creds';
  }

  String url(String path) {
    final host = config.host.endsWith('/') ? config.host.substring(0, config.host.length - 1) : config.host;
    final p = path.startsWith('/') ? path : '/$path';
    return '$host$p';
  }

  @override
  IconData get icon => Icons.cloud_rounded;

  @override
  Future<List<BookItem>> browse(String path) async {
    final client = httpClient;
    final url = this.url(path);

    final body = '''<?xml version="1.0" encoding="utf-8"?>
<D:propfind xmlns:D="DAV:">
  <D:prop>
    <D:resourcetype/>
    <D:displayname/>
  </D:prop>
</D:propfind>''';

    final response = await client.send(http.Request('PROPFIND', Uri.parse(url))
      ..headers.addAll({
        'Authorization': authHeader(),
        'Depth': '1',
        'Content-Type': 'application/xml; charset=utf-8',
      })
      ..bodyBytes = utf8.encode(body));

    final responseBody = await response.stream.bytesToString();
    if (response.statusCode >= 400) {
      throw Exception('WebDAV error ${response.statusCode}: $responseBody');
    }

    final doc = XmlDocument.parse(responseBody);
    final items = <BookItem>[];

    for (final responseElem in doc.findAllElements('D:response')) {
      final href = responseElem.findElements('D:href').firstOrNull?.innerText ?? '';
      final displayName = responseElem.findAllElements('D:displayname').firstOrNull?.innerText ?? '';
      final isCollection = responseElem.findAllElements('D:collection').isNotEmpty;

      // Skip the requested directory itself
      final decodedHref = Uri.decodeFull(href);
      if (decodedHref == '/$path' || decodedHref == path || decodedHref == '/$path/' || decodedHref == '$path/') {
        continue;
      }
      if (displayName.isEmpty || displayName == '..') continue;

      items.add(BookItem(
        name: displayName,
        path: decodedHref.startsWith('/') ? decodedHref.substring(1) : decodedHref,
        isFolder: isCollection,
      ));
    }
    items.sort((a, b) {
      if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
      return _naturalCompare(a.name, b.name);
    });
    return items;
  }

  @override
  Future<String?> getStreamUrl(String filePath) async {
    return url(filePath);
  }
}

// ─── SMB Implementation ───

class SmbSource extends BookSource {
  SmbSource(super.config);

  @override
  IconData get icon => Icons.folder_shared_rounded;

  String get _root => config.host; // e.g. \\192.168.1.100\share or Z:\

  @override
  Future<List<BookItem>> browse(String path) async {
    final dirPath = path.isEmpty ? _root : '$_root\\${path.replaceAll('/', '\\')}';
    final dir = Directory(dirPath);

    if (!await dir.exists()) {
      throw Exception('目录不存在: $dirPath');
    }

    final items = <BookItem>[];
    await for (final entity in dir.list()) {
      final name = entity.path.split(RegExp(r'[/\\]')).last;
      if (name.startsWith('.') || name.startsWith(r'$')) continue;
      final relPath = path.isEmpty ? name : '$path\\${name}';

      if (entity is Directory) {
        items.add(BookItem(name: name, path: relPath, isFolder: true));
      } else if (entity is File) {
        final ext = name.split('.').last.toLowerCase();
        if (['mp3', 'm4a', 'wav', 'flac', 'opus', 'ogg', 'aac', 'wma'].contains(ext)) {
          items.add(BookItem(name: name, path: relPath));
        }
      }
    }
    items.sort((a, b) {
      if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
      return _naturalCompare(a.name, b.name);
    });
    return items;
  }

  @override
  Future<String?> getStreamUrl(String filePath) async {
    final fullPath = '$_root\\${filePath.replaceAll('/', '\\')}';
    if (await File(fullPath).exists()) return fullPath;
    return null;
  }
}

// ─── AliyunDrive Implementation ───

class AliyunDriveSource extends BookSource {
  AliyunDriveSource(super.config);

  String? _accessToken;
  String? _driveId;
  String? _refreshToken;

  http.Client? _client;

  http.Client get _httpClient {
    _client?.close();
    final io = WebdavSource.platformHttpClient();
    final client = IOClient(io);
    _client = client;
    return client;
  }

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${_accessToken ?? ''}',
        'Content-Type': 'application/json',
      };

  @override
  IconData get icon => Icons.cloud_done_rounded;

  /// Step 1: Get access token from refresh token
  Future<bool> _ensureToken() async {
    if (_accessToken != null) return true;
    _refreshToken = config.password;
    if (_refreshToken == null || _refreshToken!.isEmpty) {
      debugPrint('[Aliyun] refresh_token is empty');
      return false;
    }

    try {
      final client = _httpClient;
      final resp = await client.post(
        Uri.parse('https://auth.aliyundrive.com/v2/account/token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'grant_type': 'refresh_token',
          'refresh_token': _refreshToken,
        }),
      );
      debugPrint('[Aliyun] token response: ${resp.statusCode}');
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        _accessToken = data['access_token'];
        _driveId = data['default_drive_id'];
        _refreshToken = data['refresh_token'];
        config.password = _refreshToken!;
        debugPrint('[Aliyun] token OK, driveId: $_driveId');
        return true;
      } else {
        debugPrint('[Aliyun] token error: ${resp.body}');
      }
    } catch (e) {
      debugPrint('[Aliyun] token exception: $e');
    }
    return false;
  }

  /// Step 2: List directory contents
  @override
  Future<List<BookItem>> browse(String path) async {
    if (!await _ensureToken()) throw Exception('无法获取阿里云盘 token，请检查 refresh_token');
    final client = _httpClient;

    // Determine parent_file_id
    var parentId = 'root';
    if (path.isNotEmpty && path != '/') {
      parentId = path; // path is the folder's file_id
    }

    final body = jsonEncode({
      'drive_id': _driveId,
      'parent_file_id': parentId,
      'limit': 100,
      'order_by': 'name',
      'order_direction': 'ASC',
    });

    debugPrint('[Aliyun] browse path=[$path] parentId=[$parentId] driveId=[$_driveId]');
    final resp = await client.post(
      Uri.parse('https://api.aliyundrive.com/adrive/v2/file/list'),
      headers: _headers,
      body: body,
    );

    debugPrint('[Aliyun] browse response: ${resp.statusCode}');
    debugPrint('[Aliyun] body: ${resp.body.substring(0, resp.body.length > 500 ? 500 : resp.body.length)}');
    if (resp.statusCode != 200) {
      throw Exception('阿里云盘错误 ${resp.statusCode}: ${resp.body}');
    }

    final data = jsonDecode(resp.body);
    debugPrint('[Aliyun] data keys: ${data.keys}');
    final rawItems = data['items'] ?? [];
    debugPrint('[Aliyun] items count: ${rawItems.length}');
    final items = <BookItem>[];
    for (final f in rawItems) {
      final name = f['name'] as String? ?? '';
      final fileId = f['file_id'] as String? ?? '';
      final isFolder = f['type'] == 'folder';
      if (name.isEmpty || fileId.isEmpty) continue;
      items.add(BookItem(name: name, path: fileId, isFolder: isFolder));
    }
    return items;
  }

  /// Step 3: Get download URL for a file
  @override
  Future<String?> getStreamUrl(String filePath) async {
    if (!await _ensureToken()) return null;
    final client = _httpClient;

    final resp = await client.post(
      Uri.parse('https://api.aliyundrive.com/v2/file/get_download_url'),
      headers: _headers,
      body: jsonEncode({
        'drive_id': _driveId,
        'file_id': filePath,
      }),
    );

    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      return data['url'] as String?;
    }
    return null;
  }
}

// ─── Source Manager ───

class SourceManager {
  static const _key = 'cloud_audiobook_sources';
  final List<BookSource> sources = [];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_key);
    if (json == null) return;

    final list = jsonDecode(json) as List<dynamic>;
    sources.clear();
    for (final item in list) {
      final config = SourceConfig.fromJson(item as Map<String, dynamic>);
      sources.add(createSource(config));
    }
  }

  BookSource createSource(SourceConfig config) {
    switch (config.type) {
      case 'webdav':
        return WebdavSource(config);
      case 'smb':
        return SmbSource(config);
      case 'aliyun':
        return AliyunDriveSource(config);
      default:
        return WebdavSource(config);
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final list = sources.map((s) => s.config.toJson()).toList();
    await prefs.setString(_key, jsonEncode(list));
  }

  void add(BookSource source) {
    sources.add(source);
    save();
  }

  void remove(int index) {
    if (index >= 0 && index < sources.length) {
      sources.removeAt(index);
      save();
    }
  }

  void toggle(int index) {
    if (index >= 0 && index < sources.length) {
      sources[index].config.enabled = !sources[index].config.enabled;
      save();
    }
  }
}
