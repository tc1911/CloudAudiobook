import 'dart:typed_data';

Future<String> createBlobUrl(Uint8List bytes, {String mimeType = 'audio/mpeg'}) async {
  throw UnsupportedError('Blob URL not supported on this platform');
}
