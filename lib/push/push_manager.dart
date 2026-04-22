import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../auth/auth_store.dart';
import 'push_fcm.dart';
import 'push_webpush.dart';

class PushManager {
  final ApiClient api;
  final AuthStore authStore;

  WebPushRegistrar? _webRegistrar;

  PushManager({required this.api, required this.authStore});

  Future<void> initAndRegisterBestEffort() async {
    if (!authStore.isLoggedIn) return;

    if (kIsWeb) {
      _webRegistrar ??= WebPushRegistrar(api: api, authStore: authStore);
      await _webRegistrar!.initBestEffort();
      return;
    }

    await FcmRegistrar(api: api, authStore: authStore).initBestEffort();
  }

  Future<void> enableWebPushFromButtonClick() async {
    if (!authStore.isLoggedIn) return;
    if (!kIsWeb) return;

    _webRegistrar ??= WebPushRegistrar(api: api, authStore: authStore);
    await _webRegistrar!.initBestEffort();
    await _webRegistrar!.enableFromButtonClick();
  }

  void stop() {
    _webRegistrar?.stop();
    _webRegistrar = null;
  }
}