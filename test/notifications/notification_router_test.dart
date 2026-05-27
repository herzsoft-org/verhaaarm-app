import 'package:flutter_test/flutter_test.dart';
import 'package:verhaaarm/notifications/notification_router.dart';

void main() {
  group('NotificationRouteData', () {
    test('maps FINE_SUGGESTIONS click target', () {
      final data = NotificationRouteData.fromPayload({
        'clickTarget': 'FINE_SUGGESTIONS',
        'type': 'FINE_SUGGESTION_CREATED',
      });

      expect(data.target, NotificationClickTarget.fineSuggestions);
      expect(data.type, 'FINE_SUGGESTION_CREATED');
    });

    test('falls back from FINE_SUGGESTION_CREATED type', () {
      final data = NotificationRouteData.fromPayload({
        'type': 'FINE_SUGGESTION_CREATED',
      });

      expect(data.target, NotificationClickTarget.fineSuggestions);
    });
  });
}
