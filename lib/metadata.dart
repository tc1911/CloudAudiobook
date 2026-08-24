import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Metadata for a book (stored in .BookInformation/metadata.json)
class BookMeta {
  static const schemaVersion = 1;
  String title;
  String author;
  String narrator;
  String cover; // relative to .BookInformation, e.g. "cover.jpg"
  String description;

  BookMeta({
    this.title = '',
    this.author = '',
    this.narrator = '',
    this.cover = '',
    this.description = '',
  });

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'title': title,
    'author': author,
    'narrator': narrator,
    'cover': cover,
    'description': description,
  };

  factory BookMeta.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != schemaVersion) {
      throw const FormatException('Unsupported metadata schema');
    }
    return BookMeta(
      title: json['title'] as String? ?? '',
      author: json['author'] as String? ?? '',
      narrator: json['narrator'] as String? ?? '',
      cover: json['cover'] as String? ?? '',
      description: json['description'] as String? ?? '',
    );
  }
}

/// Manager for .BookInformation directory
class MetadataManager {
  static const _metaDirName = '.BookInformation';
  static const _metaFileName = 'metadata.json';

  /// Get the parent folder path from a file path
  static String folderPathFromFile(String filePath) {
    final sep = filePath.contains('/') ? '/' : '\\';
    final parts = filePath.split(sep);
    if (parts.length <= 1) return filePath;
    return parts.sublist(0, parts.length - 1).join(sep);
  }

  /// Construct .BookInformation path
  static String metaDir(String folderPath) {
    final sep = folderPath.contains('/') ? '/' : '\\';
    return '$folderPath$sep$_metaDirName';
  }

  /// Synchronous read (for local/SMB paths)
  static BookMeta? readSync(String folderPath) {
    if (kIsWeb) return null;
    final metaFile = File('${metaDir(folderPath)}$_metaFileName');
    if (!metaFile.existsSync()) return null;
    try {
      final json = metaFile.readAsStringSync();
      return BookMeta.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Read metadata from a folder path (local/SMB paths only)
  static Future<BookMeta?> read(String folderPath) async {
    if (kIsWeb) return null;
    final metaFile = File('${metaDir(folderPath)}$_metaFileName');
    if (!await metaFile.exists()) return null;
    try {
      final json = await metaFile.readAsString();
      return BookMeta.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Write metadata to a folder path
  static Future<void> write(String folderPath, BookMeta meta) async {
    if (kIsWeb) return;
    final dir = Directory(metaDir(folderPath));
    if (!await dir.exists()) await dir.create(recursive: true);
    final metaFile = File('${dir.path}$_metaFileName');
    await metaFile.writeAsString(jsonEncode(meta.toJson()));
  }

  /// Check if metadata exists (sync)
  static bool existsSync(String folderPath) {
    if (kIsWeb) return false;
    return File('${metaDir(folderPath)}$_metaFileName').existsSync();
  }

  /// Check if metadata exists
  static Future<bool> exists(String folderPath) async {
    if (kIsWeb) return false;
    return await File('${metaDir(folderPath)}$_metaFileName').exists();
  }

  /// Create meta with folder name as title if not exists
  static Future<BookMeta> createDefault(String folderPath) async {
    final sep = folderPath.contains('/') ? '/' : '\\';
    final folderName = folderPath.split(sep).last;
    final meta = BookMeta(title: folderName);
    await write(folderPath, meta);
    return meta;
  }

  /// Get cover image path
  static String? coverPath(String folderPath) {
    final metaDirPath = metaDir(folderPath);
    final meta = readSync(folderPath);
    if (meta == null || meta.cover.isEmpty) return null;
    final file = File('$metaDirPath${Platform.pathSeparator}${meta.cover}');
    return file.existsSync() ? file.path : null;
  }
}
