import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';
import 'token_storage.dart';

class AuthStore extends ChangeNotifier {
  static const _kAccessToken = 'auth_access_token';
  static const _kRefreshToken = 'auth_refresh_token';

  final TokenStorage _storage;

  String? _accessToken;
  String? _refreshToken;

  AuthStore({FlutterSecureStorage? secureStorage})
      : _storage = createTokenStorage(secureStorage: secureStorage);

  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;

  bool get isLoggedIn => (_accessToken != null && _accessToken!.isNotEmpty);

  Future<void> init() async {
    _accessToken = await _storage.read(_kAccessToken);
    _refreshToken = await _storage.read(_kRefreshToken);
    notifyListeners();
  }

  Future<void> setTokens({required String accessToken, required String refreshToken}) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;

    await _storage.write(_kAccessToken, accessToken);
    await _storage.write(_kRefreshToken, refreshToken);

    notifyListeners();
  }

  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;

    await _storage.delete(_kAccessToken);
    await _storage.delete(_kRefreshToken);

    notifyListeners();
  }

  Future<bool> tryRefresh(ApiClient api) async {
    final rt = _refreshToken ?? await _storage.read(_kRefreshToken);
    if (rt == null || rt.isEmpty) return false;

    try {
      final tokens = await api.auth.refresh(refreshToken: rt);
      await setTokens(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken);
      return true;
    } catch (_) {
      await clear();
      return false;
    }
  }

  Future<void> clearAllUserData() async {
    _accessToken = null;
    _refreshToken = null;

    await _storage.deleteAll();
    notifyListeners();
  }
}
