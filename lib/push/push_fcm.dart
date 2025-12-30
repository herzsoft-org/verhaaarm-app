import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';

import '../api/api_client.dart';
import '../auth/auth_store.dart';
import '../notifications/notification_center.dart';


final FlutterLocalNotificationsPlugin _ln = FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(); // required in background isolate
  await _ensureLocalNotificationsInitialized();

  final title = message.notification?.title ?? message.data['title']?.toString() ?? 'Notification';
  final body = message.notification?.body ?? message.data['body']?.toString() ?? '';

  await _ln.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
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
  );
}

Future<void> _ensureLocalNotificationsInitialized() async {
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const init = InitializationSettings(android: androidInit);
  await _ln.initialize(init);

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

    // Android 13+ runtime permission (this is the important one)
    await androidPlugin.requestNotificationsPermission();
  }
}

class FcmRegistrar {
  final ApiClient api;
  final AuthStore authStore;

  FcmRegistrar({required this.api, required this.authStore});

  Future<void> initBestEffort() async {
    if (!authStore.isLoggedIn) return;
    if (!Platform.isAndroid) return;

    await _ensureLocalNotificationsInitialized();

    // required for background messages
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    final fm = FirebaseMessaging.instance;

    // Android 13+ runtime permission
    await fm.requestPermission();

    final token = await fm.getToken();
    if (token != null && token.isNotEmpty) {
      await api.registerFcmToken(token);
    }

    fm.onTokenRefresh.listen((t) async {
      if (!authStore.isLoggedIn) return;
      if (t.isEmpty) return;
      try {
        await api.registerFcmToken(t);
      } catch (_) {}
    });

    // Foreground: show local notification + refresh unread count
    FirebaseMessaging.onMessage.listen((msg) async {
      final title = msg.notification?.title ?? msg.data['title']?.toString() ?? 'Notification';
      final body = msg.notification?.body ?? msg.data['body']?.toString() ?? '';

      await _ln.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
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
      );

      NotificationCenter.I.refreshUnreadCount();
    });
  }
}
