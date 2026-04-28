import 'dart:typed_data';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

bool get shouldUseProtocolBrowserPdfFallbackPlatform {
  final userAgent = web.window.navigator.userAgent.toLowerCase();

  return userAgent.contains('android') ||
      userAgent.contains('iphone') ||
      userAgent.contains('ipad') ||
      userAgent.contains('ipod') ||
      userAgent.contains('mobile');
}

void openPeriodProtocolExternallyPlatform({
  required Uint8List bytes,
  required String fileName,
}) {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/pdf'),
  );

  final url = web.URL.createObjectURL(blob);

  web.window.open(url, '_blank');

  // Delay revocation a bit so the new tab has time to load the blob.
  Future<void>.delayed(const Duration(minutes: 2), () {
    web.URL.revokeObjectURL(url);
  });
}