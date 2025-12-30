import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';

import '../api/api_client.dart';
import '../auth/auth_store.dart';

class FcmRegistrar {
  final ApiClient api;
  final AuthStore authStore;

  FcmRegistrar({required this.api, required this.authStore});

  Future<void> initBestEffort() async {
    if (!authStore.isLoggedIn) return;
    if (!Platform.isAndroid) return;

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
      } catch (_) {
        // ignore; will retry next start
      }
    });
  }
}
