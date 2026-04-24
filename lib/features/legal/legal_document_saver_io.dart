import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';

Future<void> saveLegalDocumentPlatform({
  required String fileName,
  required String assetPath,
  required Uint8List bytes,
}) async {
  final baseName = fileName.replaceAll(
    RegExp(r'\.pdf$', caseSensitive: false),
    '',
  );

  await FileSaver.instance.saveAs(
    name: baseName,
    bytes: bytes,
    fileExtension: 'pdf',
    mimeType: MimeType.pdf,
  );
}