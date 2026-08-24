import 'package:flutter/material.dart';
import 'app.dart';
import 'source.dart';
import 'book_db.dart';
import 'theme_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initMediaKit();

  final sourceManager = SourceManager();
  final bookDb = BookDatabase();
  final themeManager = ThemeManager();
  await Future.wait([sourceManager.load(), bookDb.load(), themeManager.load()]);

  runApp(
    AudiobookApp(
      initialPositionMs: 0,
      sourceManager: sourceManager,
      bookDb: bookDb,
      themeManager: themeManager,
    ),
  );
}
