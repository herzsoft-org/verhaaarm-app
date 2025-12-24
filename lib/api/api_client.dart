import 'package:dio/dio.dart';

import '../auth/auth_store.dart';
import '../auth/auth_api.dart';
import '../auth/auth_interceptor.dart';
import '../models/dtos.dart';

class ApiClient {
  final AuthStore authStore;

  late final Dio dio;
  late final AuthApi auth;

  static const String baseUrlProd = 'https://verhaarmapi.herz.moe';

  ApiClient({required this.authStore}) {
    dio = Dio(BaseOptions(
      baseUrl: baseUrlProd,
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 20),
      headers: {'Content-Type': 'application/json'},
    ));

    auth = AuthApi(dio);

    dio.interceptors.add(AuthInterceptor(authStore: authStore, authApi: auth));
    // used by AuthInterceptor retry
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        options.extra['_dio_instance'] = dio;
        handler.next(options);
      },
    ));
  }

  // --- AUTH convenience (used by ProfilePage)
  Future<TokenResponse> login({required String username, required String password}) {
    return auth.login(username: username, password: password);
  }

  Future<void> logoutOnServer(String refreshToken) async {
    await auth.logout(refreshToken: refreshToken);
  }

  // --- PERIODS / BALANCE
  Future<ConventPeriodDto> getActivePeriod() async {
    final r = await dio.get('/periods/active');
    return ConventPeriodDto.fromJson(r.data as Map<String, dynamic>);
  }

  Future<UserBalanceDto> getMyBalance({String? periodId}) async {
    final r = await dio.get('/users/me/balance', queryParameters: {
      if (periodId != null) 'periodId': periodId,
    });
    return UserBalanceDto.fromJson(r.data as Map<String, dynamic>);
  }

  Future<List<ConventPeriodDto>> listPeriods() async {
    final r = await dio.get('/periods');
    final list = (r.data as List).cast<dynamic>();
    return list.map((e) => ConventPeriodDto.fromJson(e as Map<String, dynamic>)).toList();
  }

  // --- USERS (picker)
  Future<List<UserPickerDto>> pickerUsers({String? query}) async {
    final r = await dio.get('/users', queryParameters: {
      'active': true,
      if (query != null && query.trim().isNotEmpty) 'query': query.trim(),
    });
    final list = (r.data as List).cast<dynamic>();
    return list.map((e) => UserPickerDto.fromJson(e as Map<String, dynamic>)).toList();
  }

  // --- FINES
  Future<List<FineDto>> listFines() async {
    final r = await dio.get('/fines');
    final list = (r.data as List).cast<dynamic>();
    return list.map((e) => FineDto.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<FineDto> getFine(String id) async {
    final r = await dio.get('/fines/$id');
    return FineDto.fromJson(r.data as Map<String, dynamic>);
  }

  Future<FineDto> createFine(CreateFineRequest req) async {
    final r = await dio.post('/fines', data: req.toJson());
    return FineDto.fromJson(r.data as Map<String, dynamic>);
  }

  Future<FineDto> updateFine(String id, UpdateFineRequest req) async {
    final r = await dio.patch('/fines/$id', data: req.toJson());
    return FineDto.fromJson(r.data as Map<String, dynamic>);
  }

  Future<void> deleteFine(String id) async {
    await dio.delete('/fines/$id');
  }

  // --- Fine Catalog
  Future<List<FineCatalogItemDto>> listFineCatalog({bool? active}) async {
    final r = await dio.get('/fine-catalog', queryParameters: {
      if (active != null) 'active': active,
    });
    final list = (r.data as List).cast<dynamic>();
    return list.map((e) => FineCatalogItemDto.fromJson(e as Map<String, dynamic>)).toList();
  }

  // --- Fine Suggestions
  Future<List<FineSuggestionDto>> listSuggestions({String? status, bool mine = false}) async {
    final r = await dio.get('/fine-suggestions', queryParameters: {
      if (status != null) 'status': status,
      if (mine) 'mine': true,
    });
    final list = (r.data as List).cast<dynamic>();
    return list.map((e) => FineSuggestionDto.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<FineSuggestionDto> getSuggestion(String id) async {
    final r = await dio.get('/fine-suggestions/$id');
    return FineSuggestionDto.fromJson(r.data as Map<String, dynamic>);
  }

  Future<FineSuggestionDto> createSuggestion(CreateFineSuggestionRequest req) async {
    final r = await dio.post('/fine-suggestions', data: req.toJson());
    return FineSuggestionDto.fromJson(r.data as Map<String, dynamic>);
  }

  Future<void> rejectSuggestion(String id) async {
    await dio.post('/fine-suggestions/$id/reject');
  }

  Future<FineDtoAcceptResult> acceptSuggestion(String id) async {
    final r = await dio.post('/fine-suggestions/$id/accept');
    return FineDtoAcceptResult.fromJson(r.data as Map<String, dynamic>);
  }

  // --- LIVE EVENTS
  Future<List<LiveEventDto>> listLiveEvents() async {
    final r = await dio.get('/live-events');
    final list = (r.data as List).cast<dynamic>();
    return list.map((e) => LiveEventDto.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<LiveEventDto> createLiveEvent(CreateLiveEventRequest req) async {
    final r = await dio.post('/live-events', data: req.toJson());
    return LiveEventDto.fromJson(r.data as Map<String, dynamic>);
  }

  Future<LiveEventDto> updateLiveEvent(String id, UpdateLiveEventRequest req) async {
    final r = await dio.patch('/live-events/$id', data: req.toJson());
    return LiveEventDto.fromJson(r.data as Map<String, dynamic>);
  }


  Future<void> deleteLiveEvent(String id) async {
    await dio.delete('/live-events/$id');
  }

  // --- EXPORT CSV
  Future<Response<dynamic>> exportFinesCsv({String? periodId, bool includeDeleted = false}) {
    return dio.get(
      '/fines/export.csv',
      queryParameters: {
        if (periodId != null) 'periodId': periodId,
        if (includeDeleted) 'includeDeleted': true,
      },
      options: Options(
        responseType: ResponseType.bytes,
        headers: {
          'Accept': 'text/csv',
        },
      ),
    );
  }
}
