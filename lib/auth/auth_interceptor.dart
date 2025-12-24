import 'package:dio/dio.dart';

import 'auth_store.dart';
import 'auth_api.dart';

class AuthInterceptor extends Interceptor {
  final AuthStore authStore;
  final AuthApi authApi;

  AuthInterceptor({required this.authStore, required this.authApi});

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
    // If unauthorized, try refresh once and retry request
    final status = err.response?.statusCode;
    if (status != 401) {
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
      final newTokens = await authApi.refresh(refreshToken: refreshToken);
      await authStore.setTokens(
        accessToken: newTokens.accessToken,
        refreshToken: newTokens.refreshToken,
      );

      final dio = (err.requestOptions.extra['_dio_instance'] as Dio?);
      if (dio == null) {
        handler.next(err);
        return;
      }

      final RequestOptions req = err.requestOptions;
      req.headers['Authorization'] = 'Bearer ${authStore.accessToken}';

      final response = await dio.fetch(req);
      handler.resolve(response);
    } catch (_) {
      await authStore.clear();
      handler.next(err);
    }
  }
}
