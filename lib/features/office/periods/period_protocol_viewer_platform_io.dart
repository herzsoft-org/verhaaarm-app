import 'dart:typed_data';

bool get shouldUseProtocolBrowserPdfFallbackPlatform => false;

void openPeriodProtocolExternallyPlatform({
  required Uint8List bytes,
  required String fileName,
}) {
  // Native app: no-op. The in-app PDF viewer should be used.
}