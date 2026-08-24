import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'metadata.dart';

class BookRecord {
  String id;
  String title;
  String path;
  String sourceName;
  String sourceType;
  int positionMs;
  int durationMs;
  int lastPlayedAt; // millisecondsSinceEpoch
  bool favorited;
  String? coverPath;

  BookRecord({
    String? id,
    this.title = '',
    this.path = '',
    this.sourceName = '',
    this.sourceType = '',
    this.positionMs = 0,
    this.durationMs = 0,
    int? lastPlayedAt,
    this.favorited = false,
    this.coverPath,
  }) : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
       lastPlayedAt = lastPlayedAt ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'path': path,
    'sourceName': sourceName,
    'sourceType': sourceType,
    'positionMs': positionMs,
    'durationMs': durationMs,
    'lastPlayedAt': lastPlayedAt,
    'favorited': favorited,
    'coverPath': coverPath,
  };

  factory BookRecord.fromJson(Map<String, dynamic> json) => BookRecord(
    id: json['id'] as String?,
    title: json['title'] as String? ?? '',
    path: json['path'] as String? ?? '',
    sourceName: json['sourceName'] as String? ?? '',
    sourceType: json['sourceType'] as String? ?? '',
    positionMs: json['positionMs'] as int? ?? 0,
    durationMs: json['durationMs'] as int? ?? 0,
    lastPlayedAt: json['lastPlayedAt'] as int?,
    favorited: json['favorited'] as bool? ?? false,
    coverPath: json['coverPath'] as String?,
  );

  String get formattedProgress {
    if (durationMs <= 0) return '0%';
    return '${(positionMs * 100 ~/ durationMs).clamp(0, 100)}%';
  }
}

class BookDatabase {
  static const _key = 'cloud_audiobook_books';
  List<BookRecord> books = [];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_key);
    if (json != null) {
      final list = jsonDecode(json) as List<dynamic>;
      books = list
          .map((e) => BookRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(books.map((b) => b.toJson()).toList()),
    );
  }

  BookRecord? findByPath(String path, String sourceName) {
    try {
      // Match by filename part (last segment) + source name for robustness
      final targetName = path.split(RegExp(r'[/\\]')).last;
      return books.firstWhere((b) {
        final bName = b.path.split(RegExp(r'[/\\]')).last;
        return bName == targetName && b.sourceName == sourceName;
      });
    } catch (_) {
      return null;
    }
  }

  /// Find or create a record, update play position
  Future<BookRecord> touch({
    required String title,
    required String path,
    required String sourceName,
    String sourceType = 'local',
    int positionMs = 0,
    int durationMs = 0,
  }) async {
    var record = findByPath(path, sourceName);
    if (record == null) {
      record = BookRecord(
        title: title,
        path: path,
        sourceName: sourceName,
        sourceType: sourceType,
        positionMs: positionMs,
        durationMs: durationMs,
      );
      books.add(record);
    } else {
      record.positionMs = positionMs;
      record.durationMs = durationMs;
      record.lastPlayedAt = DateTime.now().millisecondsSinceEpoch;
    }
    await save();
    return record;
  }

  /// Delete a single book record
  Future<void> deleteRecord(String bookId) async {
    books.removeWhere((b) => b.id == bookId);
    await save();
  }

  /// Delete all records in a book group
  Future<void> deleteGroup(BookGroup group) async {
    final ids = group.records.map((r) => r.id).toSet();
    books.removeWhere((b) => ids.contains(b.id));
    await save();
  }

  /// Toggle favorite for entire book group
  Future<void> toggleBookFavorite(String folderKey) async {
    final group = _groupByFolder(folderKey);
    if (group == null) return;
    final newState = !group.favorited;
    for (final r in group.records) {
      r.favorited = newState;
    }
    await save();
  }

  /// Get parent folder path as grouping key
  static String folderKey(BookRecord r) {
    final sep = r.path.contains('/') ? '/' : '\\';
    final parts = r.path.split(sep);
    if (parts.length <= 1) return r.path;
    return parts.sublist(0, parts.length - 1).join(sep);
  }

  /// Aggregated book view: groups records by parent folder
  List<BookGroup> get bookGroups {
    final map = <String, List<BookRecord>>{};
    for (final r in books) {
      final key = '${r.sourceName}|${folderKey(r)}';
      map.putIfAbsent(key, () => []).add(r);
    }
    return map.entries.map((e) => BookGroup(e.value)).toList()
      ..sort((a, b) => b.lastPlayedAt.compareTo(a.lastPlayedAt));
  }

  List<BookGroup> get favorites =>
      bookGroups.where((g) => g.favorited).toList();

  List<BookGroup> get history =>
      List<BookGroup>.from(bookGroups)
        ..sort((a, b) => b.lastPlayedAt.compareTo(a.lastPlayedAt));

  BookGroup? _groupByFolder(String folderKey) {
    try {
      return bookGroups.firstWhere((g) => g.folderKey == folderKey);
    } catch (_) {
      return null;
    }
  }
}

class BookGroup {
  final List<BookRecord> records;
  BookGroup(this.records);

  String? folderPathCache;
  String get folderPath {
    if (folderPathCache != null) return folderPathCache!;
    final r = records.first;
    folderPathCache = MetadataManager.folderPathFromFile(r.path);
    return folderPathCache!;
  }

  BookMeta? _metaCache;
  bool? _metaExistsCache;

  bool get hasMeta {
    if (_metaExistsCache != null) return _metaExistsCache!;
    _metaExistsCache = MetadataManager.existsSync(folderPath);
    return _metaExistsCache!;
  }

  void refreshMeta() {
    _metaCache = null;
    _metaExistsCache = null;
  }

  BookMeta get meta {
    if (_metaCache != null) return _metaCache!;
    // Try file-based first
    try {
      final m = MetadataManager.readSync(folderPath);
      if (m != null && m.title.isNotEmpty) {
        _metaExistsCache = true;
        _metaCache = m;
        return m;
      }
    } catch (_) {}
    _metaExistsCache = false;
    _metaCache = _fallbackMeta;
    return _metaCache!;
  }

  BookMeta get _fallbackMeta => BookMeta(title: _folderTitle);

  String get _folderTitle {
    final sep = records.first.path.contains('/') ? '/' : '\\';
    final parts = records.first.path.split(sep);
    if (parts.length >= 2) return parts[parts.length - 2];
    return records.first.title;
  }

  String get title => meta.title.isNotEmpty ? meta.title : _folderTitle;
  String get author => meta.author;
  String get narrator => meta.narrator;
  String? get coverPath {
    if (kIsWeb) return null;
    // Try file-based (.BookInformation/cover.*)
    final fileCover = MetadataManager.coverPath(folderPath);
    if (fileCover != null) return fileCover;
    return null;
  }

  String get folderKey => BookDatabase.folderKey(records.first);
  String get sourceName => records.first.sourceName;
  int get totalFiles => records.length;
  int get finishedFiles =>
      records.where((r) => r.positionMs >= r.durationMs - 10000).length;

  int get lastPlayedAt =>
      records.map((r) => r.lastPlayedAt).reduce((a, b) => a > b ? a : b);

  bool get favorited => records.any((r) => r.favorited);

  int get totalDurationMs => records.fold(0, (sum, r) => sum + r.durationMs);
  int get totalPositionMs => records.fold(0, (sum, r) => sum + r.positionMs);

  BookRecord? get lastPlayedRecord {
    BookRecord? latest;
    for (final r in records) {
      if (r.positionMs > 0 &&
          (latest == null || r.lastPlayedAt > latest.lastPlayedAt)) {
        latest = r;
      }
    }
    return latest;
  }

  /// e.g. "已听3集"
  String get episodeText {
    final listened = records.where((r) => r.positionMs > 0).length;
    if (listened == 0) return '${totalFiles}集';
    return '已听$listened集';
  }

  /// e.g. "12:30 / 45:00"
  String get lastEpisodeTime {
    final last = lastPlayedRecord;
    if (last == null || last.durationMs <= 0) return '';
    final pm = last.positionMs ~/ 60000;
    final ps = (last.positionMs ~/ 1000) % 60;
    final dm = last.durationMs ~/ 60000;
    final ds = (last.durationMs ~/ 1000) % 60;
    return '${pm}:${ps.toString().padLeft(2, '0')} / ${dm}:${ds.toString().padLeft(2, '0')}';
  }

  /// e.g. "宿命之环 - 1-10.opus"
  String get lastEpisodeName => lastPlayedRecord?.title ?? '';
}
