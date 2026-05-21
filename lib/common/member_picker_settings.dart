import '../api/api_client.dart';
import 'settings/app_settings_store.dart';

class MemberPickerSettings {
  static Future<bool> hidePhilister() async {
    return AppSettingsStore.I.hidePhilister;
  }

  static Future<void> setHidePhilister(
      bool value, {
        ApiClient? api,
      }) async {
    if (api == null) return;

    await AppSettingsStore.I.setHidePhilister(api, value);
  }
}