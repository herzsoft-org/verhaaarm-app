import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';
import 'token_storage.dart';
import 'device_info_payload.dart';

class AuthStore extends ChangeNotifier {
  static const _kAccessToken = 'auth_access_token';
  static const _kRefreshToken = 'auth_refresh_token';
  static const _kSessionId = 'auth_session_id';

  String? _sessionId;

  String? get sessionId => _sessionId;

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
    _sessionId = await _storage.read(_kSessionId);
    notifyListeners();
  }

  Future<void> setTokens({
    required String accessToken,
    required String refreshToken,
    String? sessionId,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;

    if (sessionId != null && sessionId.trim().isNotEmpty) {
      _sessionId = sessionId.trim();
    }

    await _storage.write(_kAccessToken, accessToken);
    await _storage.write(_kRefreshToken, refreshToken);

    if (_sessionId != null && _sessionId!.isNotEmpty) {
      await _storage.write(_kSessionId, _sessionId!);
    }

    notifyListeners();
  }

  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
    _sessionId = null;
    await _storage.delete(_kSessionId);

    await _storage.delete(_kAccessToken);
    await _storage.delete(_kRefreshToken);

    notifyListeners();
  }

  Future<bool> tryRefresh(ApiClient api) async {
    final rt = _refreshToken ?? await _storage.read(_kRefreshToken);
    if (rt == null || rt.isEmpty) return false;

    try {
      final tokens = await api.auth.refresh(
        refreshToken: rt,
        deviceInfo: await collectDeviceInfoPayload(),
      );
      await setTokens(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        sessionId: tokens.sessionId,
      );
      return true;
    } catch (_) {
      await clear();
      return false;
    }
  }

  Future<void> clearAllUserData() async {
    _accessToken = null;
    _refreshToken = null;
    _sessionId = null;

    await _storage.deleteAll();
    notifyListeners();
  }
}
