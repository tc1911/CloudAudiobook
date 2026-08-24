import 'package:flutter_test/flutter_test.dart';

import 'package:cloud_audiobook/book_db.dart';
import 'package:cloud_audiobook/source.dart';

void main() {
  group('BookRecord', () {
    test('round trips persisted fields', () {
      final record = BookRecord(
        id: 'book-1',
        title: '第一集',
        path: 'books/1.mp3',
        sourceName: 'NAS',
        sourceType: 'webdav',
        positionMs: 1200,
        durationMs: 3600,
        lastPlayedAt: 42,
        favorited: true,
        coverPath: '/tmp/cover.jpg',
      );

      final restored = BookRecord.fromJson(record.toJson());

      expect(restored.id, record.id);
      expect(restored.title, record.title);
      expect(restored.path, record.path);
      expect(restored.sourceName, record.sourceName);
      expect(restored.positionMs, record.positionMs);
      expect(restored.durationMs, record.durationMs);
      expect(restored.lastPlayedAt, record.lastPlayedAt);
      expect(restored.favorited, isTrue);
      expect(restored.coverPath, record.coverPath);
    });

    test('formats progress safely when duration is unknown', () {
      expect(BookRecord(durationMs: 0).formattedProgress, '0%');
      expect(
        BookRecord(positionMs: 50, durationMs: 100).formattedProgress,
        '50%',
      );
    });
  });

  test('folderKey removes only the final path segment', () {
    expect(
      BookDatabase.folderKey(BookRecord(path: 'books/novel/01.mp3')),
      'books/novel',
    );
    expect(BookDatabase.folderKey(BookRecord(path: '01.mp3')), '01.mp3');
  });

  test('source sync serialization excludes credentials', () {
    final config = SourceConfig(
      id: 'source-1',
      name: 'NAS',
      host: 'https://nas.example.com/dav',
      username: 'user',
      password: 'secret',
    );

    final synced = config.toJson(includeCredentials: false);

    expect(synced['username'], 'user');
    expect(synced.containsKey('password'), isFalse);
    expect(config.toJson()['password'], 'secret');
  });
}
