import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<void> saveCsvBytes({
  required List<int> bytes,
  required String filename,
  String? shareText,
}) async {
  // Dart bytes -> JS typed array
  final jsBytes = Uint8List.fromList(bytes).toJS; // JSUint8Array :contentReference[oaicite:1]{index=1}

  // JSArray<BlobPart> bauen (package:web erwartet das)
  final blobParts = ([jsBytes] as dynamic) as JSArray<web.BlobPart>; // :contentReference[oaicite:2]{index=2}

  final blob = web.Blob(
    blobParts,
    web.BlobPropertyBag(type: 'text/csv;charset=utf-8'),
  );

  final url = web.URL.createObjectURL(blob);

  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..style.display = 'none';

  web.document.body?.append(a);
  a.click();
  a.remove();

  web.URL.revokeObjectURL(url);
}
