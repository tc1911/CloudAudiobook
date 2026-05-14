import 'dart:html';
import 'dart:typed_data';

Future<String> createBlobUrl(Uint8List bytes, {String mimeType = 'audio/mpeg'}) async {
  final blob = Blob([bytes], mimeType);
  return Url.createObjectUrlFromBlob(blob);
}
