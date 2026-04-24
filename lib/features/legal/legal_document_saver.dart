import 'dart:typed_data';

import 'legal_document_saver_io.dart'
if (dart.library.html) 'legal_document_saver_web.dart';

Future<void> saveLegalDocument({
  required String fileName,
  required String assetPath,
  required Uint8List bytes,
}) {
  return saveLegalDocumentPlatform(
    fileName: fileName,
    assetPath: assetPath,
    bytes: bytes,
  );
}