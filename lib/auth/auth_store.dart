import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthStore extends ChangeNotifier {
  static const _kAccessToken = 'access_token';
  static const _kRefreshToken = 'refresh_token';
  static const _kUsername = 'username';

  final FlutterSecureStorage _storage;

  String? _accessToken;
  String? _refreshToken;
  String? _username;
  bool _initialized = false;

  AuthStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  Future<void> init() async {
    if (_initialized) return;
    _accessToken = await _storage.read(key: _kAccessToken);
    _refreshToken = await _storage.read(key: _kRefreshToken);
    _username = await _storage.read(key: _kUsername);
    _initialized = true;
    notifyListeners();
  }

  bool get isLoggedIn => (_accessToken != null && _refreshToken != null);

  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  String? get username => _username;

  Future<void> setTokens({
    required String accessToken,
    required String refreshToken,
    required String username,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    _username = username;

    await _storage.write(key: _kAccessToken, value: accessToken);
    await _storage.write(key: _kRefreshToken, value: refreshToken);
    await _storage.write(key: _kUsername, value: username);

    notifyListeners();
  }

  Future<void> updateAccessToken(String accessToken) async {
    _accessToken = accessToken;
    await _storage.write(key: _kAccessToken, value: accessToken);
    notifyListeners();
  }

  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
    _username = null;
    await _storage.delete(key: _kAccessToken);
    await _storage.delete(key: _kRefreshToken);
    await _storage.delete(key: _kUsername);
    notifyListeners();
  }
}
