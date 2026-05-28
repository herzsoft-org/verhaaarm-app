import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../api/api_client.dart';
import '../auth/auth_store.dart';
import '../models/dtos.dart';
import '../notifications/notification_center.dart';

final FlutterLocalNotificationsPlugin _ln = FlutterLocalNotificationsPlugin();

const _defaultPushChannelId = 'verhaarm_push';
const _defaultPushChannelName = 'Push notifications';
const _liveEventActionChannelId = 'verhaarm_live_events_actions_v2';
const _liveEventActionChannelName = 'Live events';

typedef PushTapHandler = Future<void> Function(Map<String, String> data);

PushTapHandler? _onPushTap;

void setPushTapHandler(PushTapHandler handler) {
  _onPushTap = handler;
}

Map<String, String> _stringMapFromDynamicMap(Map<String, dynamic> m) {
  final out = <String, String>{};
  for (final e in m.entries) {
    final v = e.value;
    if (v == null) continue;
    out[e.key] = v.toString();
  }
  return out;
}

Map<String, String> _notificationDataFromDecoded(Map<String, dynamic> decoded) {
  final nested = decoded['data'];
  if (nested is Map) {
    return _stringMapFromDynamicMap(nested.cast<String, dynamic>());
  }
  return _stringMapFromDynamicMap(decoded);
}

bool _hasReactionActions(Map<String, dynamic> data) {
  return data['supportsActions']?.toString() == 'true' &&
      data['actionSet']?.toString() == 'LIVE_EVENT_REACTIONS';
}

Future<void> _handleTapPayload(String? payload) async {
  if (payload == null || payload.isEmpty) return;
  try {
    final decoded = jsonDecode(payload);
    if (decoded is Map) {
      final m = decoded.cast<String, dynamic>();
      await _onPushTap?.call(_stringMapFromDynamicMap(m));

      // Keep badge/UI in sync when opened via local notification tap payload.
      NotificationCenter.I.refreshUnreadCount();
    }
  } catch (_) {
    // Ignore malformed notification payloads.
  }
}

bool _isReactionAction(String? actionId) {
  return actionId == LiveEventReactionType.prost.apiValue ||
      actionId == LiveEventReactionType.ichKomme.apiValue;
}

LiveEventReactionType? _reactionTypeFromAction(String actionId) {
  return switch (actionId) {
    'PROST' => LiveEventReactionType.prost,
    'ICH_KOMME' => LiveEventReactionType.ichKomme,
    _ => null,
  };
}

String? _liveEventIdFromPayload(Map<String, String> data) {
  final endpoint = data['reactionEndpoint'];
  if (endpoint != null && endpoint.isNotEmpty) {
    final match = RegExp(
      r'/live-events/([^/]+)/reactions/\{type\}',
    ).firstMatch(endpoint);
    if (match != null) return match.group(1);
  }

  return data['liveEventId'] ??
      data['liveEventID'] ??
      data['eventId'] ??
      data['id'];
}

Future<bool> _handleReactionPayload({
  required String actionId,
  required String? payload,
  ApiClient? api,
}) async {
  debugPrint('Android notification action received: $actionId');

  final type = _reactionTypeFromAction(actionId);
  if (type == null) {
    debugPrint('Android notification action ignored: unsupported action id');
    return false;
  }

  if (payload == null || payload.isEmpty) {
    debugPrint('Android notification action ignored: empty payload');
    return false;
  }

  try {
    final decoded = jsonDecode(payload);
    if (decoded is! Map) {
      debugPrint(
        'Android notification action ignored: payload is not an object',
      );
      return false;
    }

    final data = _notificationDataFromDecoded(decoded.cast<String, dynamic>());
    if (data['supportsActions'] != 'true' ||
        data['actionSet'] != 'LIVE_EVENT_REACTIONS') {
      debugPrint(
        'Android notification action ignored: unsupported action payload',
      );
      return false;
    }

    final liveEventId = _liveEventIdFromPayload(data);
    if (liveEventId == null || liveEventId.isEmpty) {
      debugPrint('Android notification action ignored: liveEventId missing');
      return false;
    }

    if (api != null) {
      debugPrint(
        'Android notification action PUT /live-events/$liveEventId/reactions/${type.apiValue}',
      );
      await api.toggleLiveEventReaction(liveEventId: liveEventId, type: type);
      debugPrint('Android notification action completed successfully');
      return true;
    }

    final authStore = AuthStore();
    await authStore.init();

    final backgroundApi = ApiClient(authStore: authStore);

    if (!authStore.isLoggedIn) {
      final refreshed = await authStore.tryRefresh(backgroundApi);
      if (!refreshed) {
        debugPrint(
          'Android notification action failed: no authenticated session',
        );
        return false;
      }
    }

    debugPrint(
      'Android notification action PUT /live-events/$liveEventId/reactions/${type.apiValue}',
    );
    await backgroundApi.toggleLiveEventReaction(
      liveEventId: liveEventId,
      type: type,
    );

    debugPrint('Android notification action completed successfully');
    return true;
  } on DioException catch (e) {
    debugPrint(
      'Android notification action failed: status=${e.response?.statusCode ?? 'none'} path=${e.requestOptions.path}',
    );
    return false;
  } catch (e) {
    debugPrint('Android notification action failed: $e');
    return false;
  }
}

@pragma('vm:entry-point')
Future<void> notificationTapBackground(NotificationResponse resp) async {
  DartPluginRegistrant.ensureInitialized();

  final actionId = resp.actionId;
  debugPrint('Android background notification response actionId=$actionId');

  if (!_isReactionAction(actionId)) return;

  await _handleReactionPayload(actionId: actionId!, payload: resp.payload);
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // NOTE: this runs in a background isolate.
  DartPluginRegistrant.ensureInitialized();
  await Firebase.initializeApp();
  await _ensureLocalNotificationsInitialized(requestPermission: false);

  final hasReactionActions = _hasReactionActions(message.data);

  // Normal notification+data messages are displayed automatically by Android
  // when the app is backgrounded/killed. Do not duplicate those.
  //
  // Action-capable live-event messages are different: FCM's auto-displayed
  // notification cannot include flutter_local_notifications action buttons,
  // so we render those locally even if message.notification is present.
  if (message.notification != null && !hasReactionActions) return;

  final title =
      message.notification?.title ??
      message.data['title']?.toString() ??
      'Notification';

  final body =
      message.notification?.body ?? message.data['body']?.toString() ?? '';

  await _ln.show(
    id: _notificationId(message),
    title: title,
    body: body,
    notificationDetails: NotificationDetails(
      android: _androidDetailsForData(message.data),
    ),
    payload: jsonEncode(message.data),
  );
}

int _notificationId(RemoteMessage m) {
  final s =
      m.messageId ??
      '${m.sentTime?.millisecondsSinceEpoch ?? 0}:${m.data.hashCode}';
  return s.hashCode & 0x7fffffff;
}

Future<void> _ensureLocalNotificationsInitialized({
  bool requestPermission = true,
}) async {
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const init = InitializationSettings(android: androidInit);

  await _ln.initialize(
    settings: init,
    onDidReceiveNotificationResponse: (resp) async {
      final actionId = resp.actionId;
      debugPrint('Android notification response actionId=$actionId');

      if (_isReactionAction(actionId)) {
        await _handleReactionPayload(
          actionId: actionId!,
          payload: resp.payload,
        );
        return;
      }

      await _handleTapPayload(resp.payload);
    },
    onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
  );

  // If app was launched by tapping a local notification we created earlier.
  final details = await _ln.getNotificationAppLaunchDetails();
  if (details?.didNotificationLaunchApp == true) {
    await _handleTapPayload(details?.notificationResponse?.payload);
  }

  final androidPlugin = _ln
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  if (androidPlugin != null) {
    const defaultChannel = AndroidNotificationChannel(
      _defaultPushChannelId,
      _defaultPushChannelName,
      description: 'Verhåårm push notifications',
      importance: Importance.max,
    );
    const liveEventActionChannel = AndroidNotificationChannel(
      _liveEventActionChannelId,
      _liveEventActionChannelName,
      description: 'Live event notifications with quick action buttons',
      importance: Importance.max,
    );

    await androidPlugin.createNotificationChannel(defaultChannel);
    await androidPlugin.createNotificationChannel(liveEventActionChannel);

    if (requestPermission) {
      await androidPlugin.requestNotificationsPermission();
    }
  }
}

class FcmRegistrar {
  final ApiClient api;
  final AuthStore authStore;

  FcmRegistrar({required this.api, required this.authStore});

  static bool _didInit = false;

  Future<void> initBestEffort() async {
    if (!authStore.isLoggedIn) return;
    if (!Platform.isAndroid) return;
    if (_didInit) return;
    _didInit = true;

    await _ensureLocalNotificationsInitialized();

    final fm = FirebaseMessaging.instance;
    await fm.requestPermission();

    final token = await fm.getToken();
    debugPrint('FCM token: ${token ?? 'null'}');

    if (token != null && token.isNotEmpty) {
      await api.registerFcmToken(token);
      debugPrint('FCM token registered with backend');
    }

    fm.onTokenRefresh.listen((t) async {
      if (!authStore.isLoggedIn || t.isEmpty) return;
      try {
        await api.registerFcmToken(t);
      } catch (_) {
        // Keep push registration best-effort.
      }
    });

    // Foreground: always show a local notification so action-capable messages
    // get Android action buttons while the app is open.
    FirebaseMessaging.onMessage.listen((msg) async {
      final title =
          msg.notification?.title ??
          msg.data['title']?.toString() ??
          'Notification';

      final body = msg.notification?.body ?? msg.data['body']?.toString() ?? '';

      await _ln.show(
        id: _notificationId(msg),
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: _androidDetailsForData(msg.data),
        ),
        payload: jsonEncode(msg.data),
      );

      NotificationCenter.I.refreshUnreadCount();
    });

    // Background -> user tapped a system notification.
    FirebaseMessaging.onMessageOpenedApp.listen((msg) async {
      await _onPushTap?.call(_stringMapFromDynamicMap(msg.data));
      NotificationCenter.I.refreshUnreadCount();
    });

    // App launched from a notification tap.
    final initial = await fm.getInitialMessage();
    if (initial != null) {
      await _onPushTap?.call(_stringMapFromDynamicMap(initial.data));
      NotificationCenter.I.refreshUnreadCount();
    }
  }
}

AndroidNotificationDetails _androidDetailsForData(Map<String, dynamic> data) {
  final actions = _reactionActionsForData(data);
  final hasActions = actions != null && actions.isNotEmpty;

  return AndroidNotificationDetails(
    hasActions ? _liveEventActionChannelId : _defaultPushChannelId,
    hasActions ? _liveEventActionChannelName : _defaultPushChannelName,
    channelDescription: hasActions
        ? 'Live event notifications with quick action buttons'
        : 'Verhåårm push notifications',
    importance: Importance.max,
    priority: Priority.max,
    category: hasActions
        ? AndroidNotificationCategory.event
        : AndroidNotificationCategory.status,
    actions: actions,
  );
}

List<AndroidNotificationAction>? _reactionActionsForData(
  Map<String, dynamic> data,
) {
  if (!_hasReactionActions(data)) {
    return null;
  }

  final reactionTypes = (data['reactionTypes'] ?? '').toString().split(',');
  final supported = reactionTypes.map((type) => type.trim()).toSet();

  if (!supported.contains('PROST') || !supported.contains('ICH_KOMME')) {
    return null;
  }

  return const [
    AndroidNotificationAction(
      'PROST',
      '🍻 Prost!',
      showsUserInterface: false,
      cancelNotification: true,
    ),
    AndroidNotificationAction(
      'ICH_KOMME',
      '🏃 Ich komme!',
      showsUserInterface: false,
      cancelNotification: true,
    ),
  ];
}
