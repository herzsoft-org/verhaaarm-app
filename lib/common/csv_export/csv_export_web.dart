import 'dart:html' as html;

Future<void> saveCsvBytes({
  required List<int> bytes,
  required String filename,
  String? shareText,
}) async {
  final blob = html.Blob(<dynamic>[bytes], 'text/csv;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);

  final a = html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none';

  html.document.body?.children.add(a);
  a.click();
  a.remove();

  html.Url.revokeObjectUrl(url);
}
