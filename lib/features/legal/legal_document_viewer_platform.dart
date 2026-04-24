import 'legal_document_viewer_platform_io.dart'
if (dart.library.html) 'legal_document_viewer_platform_web.dart';

bool get shouldUseBrowserPdfFallback => shouldUseBrowserPdfFallbackPlatform;

void openLegalDocumentExternally(String assetPath) {
  openLegalDocumentExternallyPlatform(assetPath);
}