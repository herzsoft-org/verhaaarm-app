import 'package:dio/dio.dart';

import '../app/config.dart';
import '../auth/auth_api.dart';
import '../auth/auth_interceptor.dart';
import '../auth/auth_store.dart';
import '../models/dtos.dart';

class ApiClient {
  final Dio dio;
  final AuthApi auth;
  final AuthStore authStore;

  ApiClient({required this.authStore})
      : dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      headers: const {
        'Accept': 'application/json',
      },
    ),
  ),
        auth = AuthApi(Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl))) {
    // make the current Dio instance available to the interceptor for retry
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.extra['_dio_instance'] = dio;
          handler.next(options);
        },
      ),
    );

    dio.interceptors.add(
      AuthInterceptor(authStore: authStore, authApi: auth),
    );
  }

  // ---- Auth passthrough (Login/Logout/Refresh) ----
  Future<TokenResponse> login({required String username, required String password}) =>
      auth.login(username: username, password: password);

  Future<void> logoutOnServer(String refreshToken) => auth.logout(refreshToken: refreshToken);

  // ---- App APIs ----
  Future<ConventPeriodDto> getActivePeriod() async {
    final resp = await dio.get('/periods/active');
    return ConventPeriodDto.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<UserBalanceDto> getMyBalance({String? periodId}) async {
    final resp = await dio.get(
      '/users/me/balance',
      queryParameters: periodId == null ? null : {'periodId': periodId},
    );
    return UserBalanceDto.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<List<LiveEventDto>> listLiveEvents() async {
    final resp = await dio.get('/live-events');
    final list = (resp.data as List).cast<dynamic>();
    return list
        .map((e) => LiveEventDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
