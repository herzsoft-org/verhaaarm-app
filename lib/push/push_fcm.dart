import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../api/api_client.dart';
import '../auth/auth_store.dart';
import '../notifications/notification_center.dart';

final FlutterLocalNotificationsPlugin _ln = FlutterLocalNotificationsPlugin();

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

Future<void> _handleTapPayload(String? payload) async {
  if (payload == null || payload.isEmpty) return;
  try {
    final decoded = jsonDecode(payload);
    if (decoded is Map) {
      final m = decoded.cast<String, dynamic>();
      await _onPushTap?.call(_stringMapFromDynamicMap(m));
      // keep badge/UI in sync when opened via local notification tap payload
      NotificationCenter.I.refreshUnreadCount();
    }
  } catch (_) {
    // ignore
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // NOTE: this runs in a background isolate
  await Firebase.initializeApp();
  await _ensureLocalNotificationsInitialized();

  // Option A (notification+data): Android shows the system notification automatically
  // when app is backgrounded/killed. Avoid showing a second local notification.
  if (message.notification != null) return;

  // Data-only fallback (Option B / future): show a local notification.
  final title = message.data['title']?.toString() ?? 'Notification';
  final body = message.data['body']?.toString() ?? '';

  await _ln.show(
    _notificationId(message),
    title,
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'verhaarm_push',
        'Push notifications',
        importance: Importance.max,
        priority: Priority.high,
      ),
    ),
    payload: jsonEncode(message.data),
  );
}

int _notificationId(RemoteMessage m) {
  final s = m.messageId ?? '${m.sentTime?.millisecondsSinceEpoch ?? 0}:${m.data.hashCode}';
  return s.hashCode & 0x7fffffff;
}

Future<void> _ensureLocalNotificationsInitialized() async {
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const init = InitializationSettings(android: androidInit);

  await _ln.initialize(
    init,
    onDidReceiveNotificationResponse: (resp) async {
      await _handleTapPayload(resp.payload);
    },
  );

  // If app was launched by tapping a *local* notification we created earlier
  final details = await _ln.getNotificationAppLaunchDetails();
  if (details?.didNotificationLaunchApp == true) {
    await _handleTapPayload(details?.notificationResponse?.payload);
  }

  final androidPlugin =
  _ln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  if (androidPlugin != null) {
    const channel = AndroidNotificationChannel(
      'verhaarm_push',
      'Push notifications',
      description: 'Verhåårm push notifications',
      importance: Importance.max,
    );
    await androidPlugin.createNotificationChannel(channel);

    await androidPlugin.requestNotificationsPermission();
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
    if (token != null && token.isNotEmpty) {
      await api.registerFcmToken(token);
    }

    fm.onTokenRefresh.listen((t) async {
      if (!authStore.isLoggedIn || t.isEmpty) return;
      try {
        await api.registerFcmToken(t);
      } catch (_) {}
    });

    // Foreground: show a local notification
    FirebaseMessaging.onMessage.listen((msg) async {
      final title = msg.notification?.title ?? msg.data['title']?.toString() ?? 'Notification';
      final body = msg.notification?.body ?? msg.data['body']?.toString() ?? '';

      await _ln.show(
        _notificationId(msg),
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'verhaarm_push',
            'Push notifications',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
        payload: jsonEncode(msg.data),
      );

      NotificationCenter.I.refreshUnreadCount();
    });

    // Background -> user tapped the system notification (Option A) or a FCM-delivered one
    FirebaseMessaging.onMessageOpenedApp.listen((msg) async {
      await _onPushTap?.call(_stringMapFromDynamicMap(msg.data));
      NotificationCenter.I.refreshUnreadCount();
    });

    // App launched from a notification tap (system notification)
    final initial = await fm.getInitialMessage();
    if (initial != null) {
      await _onPushTap?.call(_stringMapFromDynamicMap(initial.data));
      NotificationCenter.I.refreshUnreadCount();
    }
  }
}
