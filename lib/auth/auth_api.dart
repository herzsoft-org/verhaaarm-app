import 'package:dio/dio.dart';
import '../models/dtos.dart';

class AuthApi {
  final Dio _dio;

  AuthApi(this._dio);

  static const _kSkipRefresh = 'skip_auth_refresh';

  Future<TokenResponse> login({
    required String username,
    required String password,
    Map<String, dynamic>? deviceInfo,
  }) async {
    final resp = await _dio.post(
      '/auth/login',
      data: {
        'username': username,
        'password': password,
        if (deviceInfo != null && deviceInfo.isNotEmpty) 'deviceInfo': deviceInfo,
      },
      options: Options(extra: {_kSkipRefresh: true}),
    );
    return TokenResponse.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<TokenResponse> refresh({
    required String refreshToken,
    Map<String, dynamic>? deviceInfo,
  }) async {
    final resp = await _dio.post(
      '/auth/refresh',
      data: {
        'refreshToken': refreshToken,
        if (deviceInfo != null && deviceInfo.isNotEmpty) 'deviceInfo': deviceInfo,
      },
      options: Options(extra: {_kSkipRefresh: true}),
    );
    return TokenResponse.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<void> logout({required String refreshToken}) async {
    await _dio.post(
      '/auth/logout',
      data: {'refreshToken': refreshToken},
      options: Options(extra: {_kSkipRefresh: true}),
    );
  }
}