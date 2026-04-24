import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<void> saveLegalDocumentPlatform({
  required String fileName,
  required String assetPath,
  required Uint8List bytes,
}) async {
  final encodedPath = assetPath
      .split('/')
      .map(Uri.encodeComponent)
      .join('/');

  final assetUrl = 'assets/$encodedPath';

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
    return;
  }

  final anchor = web.HTMLAnchorElement()
    ..href = assetUrl
    ..download = fileName
    ..target = '_blank'
    ..style.display = 'none';

  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
}