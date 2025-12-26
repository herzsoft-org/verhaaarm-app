import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class TokenStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<void> deleteAll();
}

class SecureTokenStorage implements TokenStorage {
  final FlutterSecureStorage _storage;
  SecureTokenStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}

class WebPrefsTokenStorage implements TokenStorage {
  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  Future<String?> read(String key) async => (await _prefs).getString(key);

  @override
  Future<void> write(String key, String value) async => (await _prefs).setString(key, value);

  @override
  Future<void> delete(String key) async => (await _prefs).remove(key);

  @override
  Future<void> deleteAll() async => (await _prefs).clear();
}

TokenStorage createTokenStorage({FlutterSecureStorage? secureStorage}) {
  if (kIsWeb) return WebPrefsTokenStorage();
  return SecureTokenStorage(secureStorage);
}
