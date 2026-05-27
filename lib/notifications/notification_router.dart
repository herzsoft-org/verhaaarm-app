import 'dart:convert';

import 'package:go_router/go_router.dart';

enum NotificationClickTarget {
  homeLiveEvents,
  actionsArbeitsauftraege,
  actionsBeihaengung,
  fineSuggestions,
  unknown,
}

class NotificationRouteData {
  final NotificationClickTarget target;
  final String? type;

  const NotificationRouteData({required this.target, this.type});

  factory NotificationRouteData.fromPayload(Map<String, String> payload) {
    final normalized = <String, String>{...payload};

    final nested = payload['data'];
    if (nested != null && nested.trim().startsWith('{')) {
      // WebPush normally stores metadata inside data. Some app paths may pass
      // that object through as a string, so keep this parser defensive.
      try {
        final decoded = jsonDecode(nested);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final value = entry.value;
            if (value != null) {
              normalized[entry.key.toString()] = value.toString();
            }
          }
        }
      } catch (_) {
        // ignore malformed metadata
      }
    }

    final target = (normalized['clickTarget'] ?? '').trim().toUpperCase();
    final type = (normalized['type'] ?? normalized['notificationType'])?.trim();

    return NotificationRouteData(
      target: switch (target) {
        'HOME_LIVE_EVENTS' => NotificationClickTarget.homeLiveEvents,
        'ACTIONS_ARBEITSAUFTRAEGE' =>
          NotificationClickTarget.actionsArbeitsauftraege,
        'ACTIONS_BEIHAENGUNG' => NotificationClickTarget.actionsBeihaengung,
        'FINE_SUGGESTIONS' => NotificationClickTarget.fineSuggestions,
        _ => _targetFromType(type),
      },
      type: type,
    );
  }

  static NotificationClickTarget _targetFromType(String? type) {
    final t = (type ?? '').toUpperCase();
    if (t.contains('LIVE_EVENT')) return NotificationClickTarget.homeLiveEvents;
    if (t.contains('TASK')) {
      return NotificationClickTarget.actionsArbeitsauftraege;
    }
    if (t == 'FINE_SUGGESTION_CREATED') {
      return NotificationClickTarget.fineSuggestions;
    }
    if (t.contains('FINE')) return NotificationClickTarget.actionsBeihaengung;
    return NotificationClickTarget.unknown;
  }
}

Future<void> routeNotificationClick(
  GoRouter router,
  Map<String, String> payload,
) async {
  final data = NotificationRouteData.fromPayload(payload);

  switch (data.target) {
    case NotificationClickTarget.homeLiveEvents:
      router.go('/home');
      return;
    case NotificationClickTarget.actionsArbeitsauftraege:
      router.go('/actions');
      router.push('/tasks');
      return;
    case NotificationClickTarget.actionsBeihaengung:
      router.go('/actions');
      router.push('/my-fines');
      return;
    case NotificationClickTarget.fineSuggestions:
      router.go('/office/fine-suggestions');
      return;
    case NotificationClickTarget.unknown:
      router.go('/home');
      return;
  }
}
