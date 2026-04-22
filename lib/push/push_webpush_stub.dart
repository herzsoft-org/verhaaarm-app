import '../api/api_client.dart';
import '../auth/auth_store.dart';

class WebPushRegistrar {
  final ApiClient api;
  final AuthStore authStore;

  WebPushRegistrar({required this.api, required this.authStore});

  Future<void> initBestEffort() async {
    // not web
  }

  Future<void> enableFromButtonClick() async {
    // not web
  }

  void stop() {}
}
