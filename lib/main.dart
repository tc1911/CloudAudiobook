import 'package:flutter/material.dart';
import 'app.dart';
import 'source.dart';
import 'book_db.dart';
import 'theme_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initMediaKit();

  final sourceManager = SourceManager();
  final bookDb = BookDatabase();
  sourceManager.load();
  bookDb.load();

  final themeManager = ThemeManager();
  await themeManager.load();

  runApp(AudiobookApp(
    initialPositionMs: 0,
    sourceManager: sourceManager,
    bookDb: bookDb,
    themeManager: themeManager,
  ));
}
