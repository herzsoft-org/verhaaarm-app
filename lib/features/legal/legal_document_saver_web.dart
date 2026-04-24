import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'legal_document_save_result.dart';

Future<LegalDocumentSaveResult> saveLegalDocumentPlatform({
  required String fileName,
  required String assetPath,
  required Uint8List bytes,
}) async {
  final assetUrl = legalDocumentAssetUrl(assetPath);

  final userAgent = web.window.navigator.userAgent.toLowerCase();

  final isIos = userAgent.contains('iphone') ||
      userAgent.contains('ipad') ||
      userAgent.contains('ipod');

  final isSafari = userAgent.contains('safari') &&
      !userAgent.contains('chrome') &&
      !userAgent.contains('crios') &&
      !userAgent.contains('fxios') &&
      !userAgent.contains('edgios');

  if (isIos || isSafari) {
    web.window.open(assetUrl, '_blank');
    return LegalDocumentSaveResult.opened;
  }

  final anchor = web.HTMLAnchorElement()
    ..href = assetUrl
    ..download = fileName
    ..target = '_blank'
    ..style.display = 'none';

  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();

  return LegalDocumentSaveResult.saved;
}

String legalDocumentAssetUrl(String assetPath) {
  final encodedPath = assetPath
      .split('/')
      .map(Uri.encodeComponent)
      .join('/');

  return 'assets/$encodedPath';
}

bool isMobileWebBrowser() {
  final userAgent = web.window.navigator.userAgent.toLowerCase();

  return userAgent.contains('android') ||
      userAgent.contains('iphone') ||
      userAgent.contains('ipad') ||
      userAgent.contains('ipod') ||
      userAgent.contains('mobile');
}

void openLegalDocumentInBrowser(String assetPath) {
  web.window.open(legalDocumentAssetUrl(assetPath), '_blank');
}