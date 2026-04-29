import 'cache/app_cache.dart';

class MemberPickerSettings {
  static const hidePhilisterKey = 'member_picker.hide_philister';

  static Future<bool> hidePhilister() async {
    return await AppCache.I.getPersistedBool(hidePhilisterKey) ?? false;
  }

  static Future<void> setHidePhilister(bool value) async {
    await AppCache.I.setPersistedBool(hidePhilisterKey, value);
  }
}