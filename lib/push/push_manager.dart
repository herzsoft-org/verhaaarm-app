import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../auth/auth_store.dart';
import 'push_fcm.dart';
import 'push_webpush.dart';

class PushManager {
  final ApiClient api;
  final AuthStore authStore;

  PushManager({required this.api, required this.authStore});

  Future<void> initAndRegisterBestEffort() async {
    if (!authStore.isLoggedIn) return;

    if (kIsWeb) {
      await WebPushRegistrar(api: api, authStore: authStore).initBestEffort();
      return;
    }

    await FcmRegistrar(api: api, authStore: authStore).initBestEffort();
  }

  Future<void> enableWebPushFromButtonClick() async {
    if (!authStore.isLoggedIn) return;
    if (!kIsWeb) return;

    await WebPushRegistrar(api: api, authStore: authStore).enableFromButtonClick();
  }
}
