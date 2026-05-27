import 'package:flutter_test/flutter_test.dart';
import 'package:verhaaarm/common/widgets/app_scaffold.dart';

void main() {
  group('mainTabIndexForLocation', () {
    test('keeps actions feature pages in the actions tab', () {
      const actionsLocations = [
        '/actions',
        '/tasks',
        '/tasks/123/edit',
        '/my-fine-suggestions',
        '/suggestions/new',
        '/my-fines',
        '/fines/new',
        '/office',
        '/office/fine-suggestions',
        '/office/fechtwart/paukstunden/new',
        '/paukstunden/me',
        '/convent-protocols',
        '/legal-documents/Satzung',
      ];

      for (final location in actionsLocations) {
        expect(
          mainTabIndexForLocation(location),
          1,
          reason: '$location should select Aktionen',
        );
      }
    });

    test('keeps profile pages in the profile tab', () {
      expect(mainTabIndexForLocation('/profile'), 2);
      expect(mainTabIndexForLocation('/profile/sessions'), 2);
    });

    test('falls back to home for home and unrelated pages', () {
      expect(mainTabIndexForLocation('/home'), 0);
      expect(mainTabIndexForLocation('/notifications'), 0);
    });
  });
}
