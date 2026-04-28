import 'dart:typed_data';

import 'period_protocol_viewer_platform_io.dart'
if (dart.library.html) 'period_protocol_viewer_platform_web.dart';

bool get shouldUseProtocolBrowserPdfFallback =>
    shouldUseProtocolBrowserPdfFallbackPlatform;

void openPeriodProtocolExternally({
  required Uint8List bytes,
  required String fileName,
}) {
  openPeriodProtocolExternallyPlatform(
    bytes: bytes,
    fileName: fileName,
  );
}