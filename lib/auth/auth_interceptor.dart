import 'dart:async';
import 'package:dio/dio.dart';

import 'auth_store.dart';
import 'auth_api.dart';
import 'device_info_payload.dart';

class AuthInterceptor extends Interceptor {
  final AuthStore authStore;
  final AuthApi authApi;

  AuthInterceptor({required this.authStore, required this.authApi});

  Future<void>? _refreshing; // single-flight without TokenResponse type dependency

  bool _shouldSkip(RequestOptions o) {
    final path = o.path;
    if (path.startsWith('/auth/')) return true;
    if (o.extra['skip_auth_refresh'] == true) return true;
    return false;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = authStore.accessToken;
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final status = err.response?.statusCode;

    // Only handle 401 for non-auth endpoints
    if (status != 401 || _shouldSkip(err.requestOptions)) {
      handler.next(err);
      return;
    }

    final refreshToken = authStore.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      await authStore.clear();
      handler.next(err);
      return;
    }

    try {
      // Start refresh once; others await same future.
      _refreshing ??= () async {
        final newTokens = await authApi.refresh(
          refreshToken: refreshToken,
          deviceInfo: await collectDeviceInfoPayload(),
        );
        await authStore.setTokens(
          accessToken: newTokens.accessToken,
          refreshToken: newTokens.refreshToken,
          sessionId: newTokens.sessionId,
        );
      }();

      await _refreshing!;
      _refreshing = null;

      final dio = (err.requestOptions.extra['_dio_instance'] as Dio?);
      if (dio == null) {
        handler.next(err);
        return;
      }

      final req = err.requestOptions;

      // prevent infinite retry loops
      if (req.extra['__retried'] == true) {
        handler.next(err);
        return;
      }
      req.extra['__retried'] = true;

      req.headers['Authorization'] = 'Bearer ${authStore.accessToken}';

      final response = await dio.fetch(req);
      handler.resolve(response);
    } catch (_) {
      _refreshing = null;
      await authStore.clear();
      handler.next(err);
    }
  }
}
