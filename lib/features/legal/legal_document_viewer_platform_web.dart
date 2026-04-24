import 'package:web/web.dart' as web;

bool get shouldUseBrowserPdfFallbackPlatform {
  final userAgent = web.window.navigator.userAgent.toLowerCase();

  return userAgent.contains('android') ||
      userAgent.contains('iphone') ||
      userAgent.contains('ipad') ||
      userAgent.contains('ipod') ||
      userAgent.contains('mobile');
}

void openLegalDocumentExternallyPlatform(String assetPath) {
  final encodedPath = assetPath
      .split('/')
      .map(Uri.encodeComponent)
      .join('/');

  final assetUrl = 'assets/$encodedPath';

  web.window.open(assetUrl, '_blank');
}