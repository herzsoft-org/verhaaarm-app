import 'package:flutter_test/flutter_test.dart';
import 'package:verhaaarm/features/legal/legal_document.dart';

void main() {
  group('LegalDocument', () {
    test('contains unique ids and file names', () {
      final ids = LegalDocument.all.map((doc) => doc.id).toSet();
      final fileNames = LegalDocument.all.map((doc) => doc.fileName).toSet();

      expect(ids, hasLength(LegalDocument.all.length));
      expect(fileNames, hasLength(LegalDocument.all.length));
    });

    test('looks up documents by id', () {
      final document = LegalDocument.byId('satzung-2013');

      expect(document, isNotNull);
      expect(document!.title, 'Satzung (Stand 2013)');
      expect(document.assetPath, 'assets/legal/Satzung_2013.pdf');
    });

    test('returns null for unknown ids', () {
      expect(LegalDocument.byId('missing'), isNull);
    });
  });
}
