import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';

class AuthStore extends ChangeNotifier {
  static const _kAccessToken = 'auth_access_token';
  static const _kRefreshToken = 'auth_refresh_token';

  final FlutterSecureStorage _storage;

  String? _accessToken;
  String? _refreshToken;

  AuthStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;

  bool get isLoggedIn => (_accessToken != null && _accessToken!.isNotEmpty);

  Future<void> init() async {
    _accessToken = await _storage.read(key: _kAccessToken);
    _refreshToken = await _storage.read(key: _kRefreshToken);
    notifyListeners();
  }

  Future<void> setTokens({required String accessToken, required String refreshToken}) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;

    await _storage.write(key: _kAccessToken, value: accessToken);
    await _storage.write(key: _kRefreshToken, value: refreshToken);

    notifyListeners();
  }

  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;

    await _storage.delete(key: _kAccessToken);
    await _storage.delete(key: _kRefreshToken);

    notifyListeners();
  }

  /// Try to refresh at app start (or on demand)
  Future<bool> tryRefresh(ApiClient api) async {
    final rt = _refreshToken ?? await _storage.read(key: _kRefreshToken);
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
}
