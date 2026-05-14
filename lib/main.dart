import 'package:flutter/material.dart';
import 'app.dart';
import 'source.dart';
import 'book_db.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  initMediaKit();

  final sourceManager = SourceManager();
  final bookDb = BookDatabase();
  sourceManager.load();
  bookDb.load();

  runApp(AudiobookApp(
    initialPositionMs: 0,
    sourceManager: sourceManager,
    bookDb: bookDb,
  ));
}
