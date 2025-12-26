import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../auth/auth_api.dart';
import '../auth/auth_interceptor.dart';
import '../auth/auth_store.dart';
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
      // no global Content-Type; Dio will set it per request
      headers: {},
    ));

    auth = AuthApi(dio);

    dio.interceptors.add(AuthInterceptor(authStore: authStore, authApi: auth));
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

  Future<UserDto> getMe() async {
    final res = await dio.get('/users/me');
    return UserDto.fromJson((res.data as Map).cast<String, dynamic>());
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

  // --- FINES: PHOTOS
  Future<List<FinePhotoDto>> listFinePhotos(String fineId) async {
    final r = await dio.get('/fines/$fineId/photos');
    final list = (r.data as List).cast<dynamic>();
    return list.map((e) => FinePhotoDto.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<FinePhotoDto> uploadFinePhoto({
    required String fineId,
    required String filePath,
    required String filename,
  }) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: filename),
    });

    final r = await dio.post(
      '/fines/$fineId/photos',
      data: form,
      options: Options(
        contentType: 'multipart/form-data',
      ),
    );

    return FinePhotoDto.fromJson(r.data as Map<String, dynamic>);
  }

  Future<Uint8List> downloadFinePhotoBytes({
    required String fineId,
    required String photoId,
  }) async {
    final r = await dio.get(
      '/fines/$fineId/photos/$photoId/download',
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList((r.data as List<int>));
  }

  Future<void> deleteFinePhoto({
    required String fineId,
    required String photoId,
  }) async {
    await dio.delete('/fines/$fineId/photos/$photoId');
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

  // --- EVENTS (scheduled events / calendar)
  Future<List<EventDto>> listEvents() async {
    final r = await dio.get('/events');
    final list = (r.data as List).cast<dynamic>();
    return list.map((e) => EventDto.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<EventDto> getEvent(String id) async {
    final r = await dio.get('/events/$id');
    return EventDto.fromJson(r.data as Map<String, dynamic>);
  }

  Future<EventDto> createEvent(CreateEventRequest req) async {
    final r = await dio.post('/events', data: req.toJson());
    return EventDto.fromJson(r.data as Map<String, dynamic>);
  }

  Future<EventDto> updateEvent(String id, UpdateEventRequest req) async {
    final r = await dio.patch('/events/$id', data: req.toJson());
    return EventDto.fromJson(r.data as Map<String, dynamic>);
  }

  Future<void> deleteEvent(String id) async {
    await dio.delete('/events/$id');
  }

  // --- ATTENDANCE
  Future<List<AttendanceDto>> listAttendance(String eventId) async {
    final r = await dio.get('/events/$eventId/attendance');
    final list = (r.data as List).cast<dynamic>();
    return list.map((e) => AttendanceDto.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<AttendanceDto> upsertAttendance(String eventId, UpsertAttendanceRequest req) async {
    final r = await dio.put('/events/$eventId/attendance', data: req.toJson());
    return AttendanceDto.fromJson(r.data as Map<String, dynamic>);
  }

  Future<void> deleteAttendance(String eventId, String userId) async {
    await dio.delete('/events/$eventId/attendance/$userId');
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

  // --- USERS (admin/senior)
  Future<List<UserDto>> listUsersFull({required bool active}) async {
    final r = await dio.get('/users', queryParameters: {'active': active});
    final list = (r.data as List).cast<dynamic>();
    return list.map((e) => UserDto.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<UserDto> createUser(CreateUserRequest req) async {
    final r = await dio.post('/users', data: req.toJson());
    return UserDto.fromJson(r.data as Map<String, dynamic>);
  }

  Future<UserDto> getUser(String id) async {
    final r = await dio.get('/users/$id');
    return UserDto.fromJson(r.data as Map<String, dynamic>);
  }

  Future<UserDto> updateUser(String id, UpdateUserRequest req) async {
    final r = await dio.patch('/users/$id', data: req.toJson());
    return UserDto.fromJson(r.data as Map<String, dynamic>);
  }

  Future<void> setUserPassword(String id, String newPassword) async {
    await dio.patch('/users/$id/password', data: {'password': newPassword});
  }

  // --- Fine Catalog CRUD (admin)
  Future<FineCatalogItemDto> createFineCatalogItem(CreateFineCatalogItemRequest req) async {
    final r = await dio.post('/fine-catalog', data: req.toJson());
    return FineCatalogItemDto.fromJson(r.data as Map<String, dynamic>);
  }

  Future<FineCatalogItemDto> getFineCatalogItem(String id) async {
    final r = await dio.get('/fine-catalog/$id');
    return FineCatalogItemDto.fromJson(r.data as Map<String, dynamic>);
  }

  Future<FineCatalogItemDto> updateFineCatalogItem(String id, UpdateFineCatalogItemRequest req) async {
    final r = await dio.patch('/fine-catalog/$id', data: req.toJson());
    return FineCatalogItemDto.fromJson(r.data as Map<String, dynamic>);
  }

  Future<void> deleteFineCatalogItem(String id) async {
    await dio.delete('/fine-catalog/$id');
  }

  Future<ConventPeriodDto> getPeriod(String id) async {
    final r = await dio.get('/periods/$id');
    return ConventPeriodDto.fromJson(r.data as Map<String, dynamic>);
  }

  Future<ConventPeriodDto> createPeriod(CreateConventPeriodRequest req) async {
    final r = await dio.post('/periods', data: req.toJson());
    return ConventPeriodDto.fromJson(r.data as Map<String, dynamic>);
  }

  Future<ConventPeriodDto> updatePeriod(String id, UpdateConventPeriodRequest req) async {
    final r = await dio.patch('/periods/$id', data: req.toJson());
    return ConventPeriodDto.fromJson(r.data as Map<String, dynamic>);
  }

  Future<ConventPeriodDto> activatePeriod(String id) async {
    final r = await dio.post('/periods/$id/activate');
    return ConventPeriodDto.fromJson(r.data as Map<String, dynamic>);
  }

  Future<ConventPeriodDto> lockPeriod(String id) async {
    final r = await dio.post('/periods/$id/lock');
    return ConventPeriodDto.fromJson(r.data as Map<String, dynamic>);
  }

  Future<ConventPeriodDto> unlockPeriod(String id) async {
    final r = await dio.patch('/periods/$id', data: {'locked': false});
    return ConventPeriodDto.fromJson(r.data as Map<String, dynamic>);
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
