import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> saveCsvBytes({
  required List<int> bytes,
  required String filename,
  String? shareText,
}) async {
  final dir = await getTemporaryDirectory();
  final path = '${dir.path}/$filename';

  final f = File(path);
  await f.writeAsBytes(bytes, flush: true);

  await SharePlus.instance.share(
    ShareParams(
      text: shareText ?? filename,
      files: [XFile(path, mimeType: 'text/csv')],
    ),
  );
}
