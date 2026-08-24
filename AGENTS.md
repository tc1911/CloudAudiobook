# Agent Guide

## Project Shape

- This is a single Flutter app (`cloud_audiobook`), not a Dart package workspace. The Dart SDK constraint is `^3.11.5`; use a compatible stable Flutter SDK.
- The runtime entrypoint is `lib/main.dart`: it initializes media playback, loads `SourceManager`, `BookDatabase`, and `ThemeManager`, then starts `AudiobookApp` from `lib/app.dart`.
- Most player behavior and UI currently lives in `lib/app.dart`; storage/source models are in `lib/book_db.dart` and `lib/source.dart`, with feature screens under `lib/screens/`.
- User data is persisted through `shared_preferences` (source configuration, book history/metadata, playback positions). Avoid changing preference keys or serialized fields without considering existing local data.
- `lib/source.dart` implements local files, WebDAV, and SMB sources. WebDAV uses Basic auth and deliberately accepts self-signed certificates; preserve that behavior unless the task explicitly changes security policy.

## Commands

- Install or refresh dependencies with `flutter pub get`; dependency versions are locked in `pubspec.lock`.
- Run static checks with `flutter analyze` (rules come from `package:flutter_lints/flutter.yaml` via `analysis_options.yaml`).
- Run tests with `flutter test`; target one file with `flutter test test/<name>_test.dart` or one test with `flutter test test/<name>_test.dart --plain-name 'test name'`.
- The only checked-in test is the untouched Flutter counter template and references the removed `MyApp`; update or replace it before treating test results as application coverage.

## Builds

- GitHub Actions is defined in `.github/workflows/build.yml`: pushes to `master`, `v*` tags, pull requests, and manual runs execute analyze/tests and build Android, Windows, and Linux artifacts.
- Linux/macOS shell wrapper: `./scripts/build.sh [windows|android|linux|all] [debug|profile|release]` (defaults to `all release`). It runs `flutter pub get` and copies products to the sibling `../app/<Mode>/<platform>/` directory.
- Windows wrapper: `scripts\build.bat [windows|android|all] [debug|profile|release]`; it supports Windows and Android only and also writes to the sibling `..\app` directory.
- The shell `all` path attempts Windows and Android before Linux; use a platform-specific argument when the host/toolchain cannot build every target.
- Windows builds download the media_kit mpv archive into `build/windows/x64/` if absent. Linux packaging downloads `appimagetool-x86_64.AppImage` into the repository and produces AppImage, `.deb`, `.rpm`, and Arch `.pkg.tar.zst` artifacts; `dpkg-deb`, `rpmbuild`, and `makepkg` are optional host tools and missing ones are skipped.
- Linux tray builds require the Ayatana AppIndicator development package (`libayatana-appindicator3-dev` on Ubuntu, `libayatana-appindicator` on Arch).
- Android release signing uses ignored `android/key.properties` and its referenced keystore when present; otherwise the Gradle config falls back to the debug signing key.

## Generated Files

- Do not hand-edit `.dart_tool/`, `build/`, platform Flutter plugin registrants, or other generated build output. `build/`, `/app/`, and Android signing material are ignored by `.gitignore`.
- After changing `pubspec.yaml`, run `flutter pub get` and review the resulting `pubspec.lock` change.
