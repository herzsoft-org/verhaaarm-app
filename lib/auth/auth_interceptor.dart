import 'package:dio/dio.dart';

import 'auth_api.dart';
import 'auth_store.dart';

class AuthInterceptor extends Interceptor {
  final AuthStore authStore;
  final AuthApi authApi;

  bool _isRefreshing = false;

  AuthInterceptor({required this.authStore, required this.authApi});

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = authStore.accessToken;
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    // Nur bei 401 versuchen wir refresh + retry
    final status = err.response?.statusCode;
    final alreadyRetried = err.requestOptions.extra['retried'] == true;

    if (status != 401 || alreadyRetried) {
      handler.next(err);
      return;
    }

    final refreshToken = authStore.refreshToken;
    if (refreshToken == null) {
      handler.next(err);
      return;
    }

    try {
      // Einfach halten: nur ein Refresh zur Zeit
      if (_isRefreshing) {
        // Falls parallel mehrere Requests 401 liefern, warten wir kurz und versuchen dann nochmal.
        await Future<void>.delayed(const Duration(milliseconds: 250));
      } else {
        _isRefreshing = true;
        final newTokens = await authApi.refresh(refreshToken: refreshToken);
        await authStore.setTokens(
          accessToken: newTokens.accessToken,
          refreshToken: newTokens.refreshToken,
          username: authStore.username ?? '',
        );
        _isRefreshing = false;
      }

      final dio = err.requestOptions
          .extra['_dio_instance'] as Dio?; // optional
      final client = dio ?? Dio();

      final opts = err.requestOptions;
      final newOptions = Options(
        method: opts.method,
        headers: Map<String, dynamic>.from(opts.headers)
          ..['Authorization'] = 'Bearer ${authStore.accessToken}',
      );

      final retryResponse = await client.request(
        opts.path,
        data: opts.data,
        queryParameters: opts.queryParameters,
        options: newOptions,
        cancelToken: opts.cancelToken,
        onReceiveProgress: opts.onReceiveProgress,
        onSendProgress: opts.onSendProgress,
      );

      handler.resolve(retryResponse);
      return;
    } catch (_) {
      _isRefreshing = false;
      await authStore.clear();
      handler.next(err);
      return;
    }
  }
}
