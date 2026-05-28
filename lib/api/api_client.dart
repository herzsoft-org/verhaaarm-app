import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http_parser/http_parser.dart';

import '../auth/auth_api.dart';
import '../auth/auth_interceptor.dart';
import '../auth/auth_store.dart';
import '../models/dtos.dart';
import '../auth/device_info_payload.dart';

class ApiClient {
  final AuthStore authStore;

  late final Dio dio;
  late final AuthApi auth;

  static const String baseUrlProd = 'https://verhaarmapi.herz.moe';
  static const Duration _defaultSendTimeout = Duration(seconds: 20);

  ApiClient({required this.authStore}) {
    dio = Dio(
      BaseOptions(
        baseUrl: baseUrlProd,
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 20),
        // don't set global Content-Type; Dio sets it per request
        headers: const {},
      ),
    );

    auth = AuthApi(dio);

    dio.interceptors.add(AuthInterceptor(authStore: authStore, authApi: auth));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          // allow AuthInterceptor / others to access the client
          options.extra['_dio_instance'] = dio;
          _applySendTimeoutIfRequestHasBody(options);
          handler.next(options);
        },
      ),
    );
  }

  void _applySendTimeoutIfRequestHasBody(RequestOptions options) {
    if (options.sendTimeout != null || !_hasRequestBody(options)) return;
    options.sendTimeout = _defaultSendTimeout;
  }

  bool _hasRequestBody(RequestOptions options) {
    final data = options.data;
    if (data == null) return false;

    if (kIsWeb) {
      if (data is String && data.isEmpty) return false;
      if (data is List && data.isEmpty) return false;
      if (data is Map && data.isEmpty) return false;
      if (data is FormData && data.fields.isEmpty && data.files.isEmpty) {
        return false;
      }
    }

    return true;
  }

  Future<ConventPeriodDto> unlockPeriod(String id) async {
    // No dedicated /unlock endpoint in swagger; unlock via PATCH locked=false
    final r = await dio.patch('/periods/$id', data: const {'locked': false});
    return ConventPeriodDto.fromJson((r.data as Map).cast<String, dynamic>());
  }

  // ----------------------------
  // AUTH convenience (swagger: /auth/login, /auth/refresh, /auth/logout)
  // ----------------------------
  Future<TokenResponse> login({
    required String username,
    required String password,
  }) async {
    return auth.login(
      username: username,
      password: password,
      deviceInfo: await collectDeviceInfoPayload(),
    );
  }

  Future<void> logoutOnServer(String refreshToken) async {
    await auth.logout(refreshToken: refreshToken);
  }

  // ----------------------------
  // USERS (swagger: /users, /users/{id}, /users/me, /users/*/balance, /users/{id}/password)
  // ----------------------------

  Future<List<UserPickerDto>> pickerUsers({String? query}) async {
    // swagger: GET /users?active=true&query=...
    final r = await dio.get(
      '/users',
      queryParameters: {
        'active': true,
        if (query != null && query.trim().isNotEmpty) 'query': query.trim(),
      },
    );

    final list = (r.data as List).cast<dynamic>();
    return list
        .map((e) => UserPickerDto.fromJson((e as Map).cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<List<UserDto>> listUsersFull({
    required bool active,
    String? query,
  }) async {
    final r = await dio.get(
      '/users',
      queryParameters: {
        'active': active,
        if (query != null && query.trim().isNotEmpty) 'query': query.trim(),
      },
    );

    final list = (r.data as List).cast<dynamic>();
    return list
        .map((e) => UserDto.fromJson((e as Map).cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<void> patchUserPassword({
    required String userId,
    required String newPassword,
  }) async {
    await dio.patch('/users/$userId/password', data: {'password': newPassword});
  }

  Future<List<UserDto>> listUsersAdmin({String? online}) async {
    final r = await dio.get(
      '/users',
      queryParameters: {
        if (online != null && online.trim().isNotEmpty) 'online': online.trim(),
      },
    );

    final list = (r.data as List).cast<dynamic>();
    return list
        .map((e) => UserDto.fromJson((e as Map).cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<UserDto> createUser(CreateUserRequest req) async {
    final r = await dio.post('/users', data: req.toJson());
    return UserDto.fromJson((r.data as Map).cast<String, dynamic>());
  }

  Future<UserDto> getUser(String id) async {
    final r = await dio.get('/users/$id');
    return UserDto.fromJson((r.data as Map).cast<String, dynamic>());
  }

  Future<UserDto> updateUser(String id, UpdateUserRequest req) async {
    final r = await dio.patch('/users/$id', data: req.toJson());
    return UserDto.fromJson((r.data as Map).cast<String, dynamic>());
  }

  Future<void> deleteUserHard(String userId) async {
    await dio.delete('/users/$userId');
  }

  Future<void> setUserPassword(String id, String newPassword) async {
    await dio.patch('/users/$id/password', data: {'password': newPassword});
  }

  Future<UserDto> getMe() async {
    final r = await dio.get('/users/me');
    return UserDto.fromJson((r.data as Map).cast<String, dynamic>());
  }

  Future<UserBalanceDto> getMyBalance({String? periodId}) async {
    final r = await dio.get(
      '/users/me/balance',
      queryParameters: {
        if (periodId != null && periodId.trim().isNotEmpty)
          'periodId': periodId.trim(),
      },
    );
    return UserBalanceDto.fromJson((r.data as Map).cast<String, dynamic>());
  }

  Future<UserBalanceDto> getUserBalance(
    String userId, {
    String? periodId,
  }) async {
    final r = await dio.get(
      '/users/$userId/balance',
      queryParameters: {
        if (periodId != null && periodId.trim().isNotEmpty)
          'periodId': periodId.trim(),
      },
    );
    return UserBalanceDto.fromJson((r.data as Map).cast<String, dynamic>());
  }

  Future<UserSettingsResponseDto> getMySettings() async {
    final r = await dio.get('/settings/me');
    return UserSettingsResponseDto.fromJson(
      (r.data as Map).cast<String, dynamic>(),
    );
  }

  Future<void> patchMySettings(List<UserSettingPatchDto> settings) async {
    if (settings.isEmpty) return;

    await dio.patch(
      '/settings/me',
      data: {
        'settings': settings.map((s) => s.toJson()).toList(growable: false),
      },
    );
  }

  // ----------------------------
  // PERIODS (swagger: /periods, /periods/active, /periods/{id}, /lock, /activate)
  // ----------------------------

  Future<List<ConventPeriodDto>> listPeriods() async {
    final r = await dio.get('/periods');
    final list = (r.data as List).cast<dynamic>();
    return list
        .map(
          (e) => ConventPeriodDto.fromJson((e as Map).cast<String, dynamic>()),
        )
        .toList(growable: false);
  }

  Future<ConventPeriodDto> getActivePeriod() async {
    final r = await dio.get('/periods/active');
    return ConventPeriodDto.fromJson((r.data as Map).cast<String, dynamic>());
  }

  Future<ConventPeriodDto> getPeriod(String id) async {
    final r = await dio.get('/periods/$id');
    return ConventPeriodDto.fromJson((r.data as Map).cast<String, dynamic>());
  }

  Future<ConventPeriodDto> createPeriod(CreateConventPeriodRequest req) async {
    final r = await dio.post('/periods', data: req.toJson());
    return ConventPeriodDto.fromJson((r.data as Map).cast<String, dynamic>());
  }

  Future<ConventPeriodDto> updatePeriod(
    String id,
    UpdateConventPeriodRequest req,
  ) async {
    final r = await dio.patch('/periods/$id', data: req.toJson());
    return ConventPeriodDto.fromJson((r.data as Map).cast<String, dynamic>());
  }

  Future<ConventPeriodDto> lockPeriod(String id) async {
    final r = await dio.post('/periods/$id/lock');
    return ConventPeriodDto.fromJson((r.data as Map).cast<String, dynamic>());
  }

  Future<ConventPeriodDto> activatePeriod(String id) async {
    final r = await dio.post('/periods/$id/activate');
    return ConventPeriodDto.fromJson((r.data as Map).cast<String, dynamic>());
  }

  Future<void> deletePeriod(String id) async {
    await dio.delete('/periods/$id');
  }

  // ----------------------------
  // PERIOD PROTOCOLS (/periods/{periodId}/protocol)
  // ----------------------------

  Future<ConventPeriodProtocolDto> getPeriodProtocol(String periodId) async {
    final r = await dio.get('/periods/$periodId/protocol');
    return ConventPeriodProtocolDto.fromJson(
      (r.data as Map).cast<String, dynamic>(),
    );
  }

  Future<ConventPeriodProtocolDto> uploadPeriodProtocol({
    required String periodId,
    String? filePath,
    Uint8List? bytes,
    required String filename,
    String? contentType,
  }) async {
    if ((filePath == null && bytes == null) ||
        (filePath != null && bytes != null)) {
      throw ArgumentError('Provide exactly one of filePath or bytes.');
    }

    final MultipartFile mf = (bytes != null)
        ? MultipartFile.fromBytes(
            bytes,
            filename: filename,
            contentType: contentType == null
                ? null
                : MediaType.parse(contentType),
          )
        : await MultipartFile.fromFile(
            filePath!,
            filename: filename,
            contentType: contentType == null
                ? null
                : MediaType.parse(contentType),
          );

    final form = FormData.fromMap({'file': mf});

    final r = await dio.post(
      '/periods/$periodId/protocol',
      data: form,
      options: Options(contentType: 'multipart/form-data'),
    );

    return ConventPeriodProtocolDto.fromJson(
      (r.data as Map).cast<String, dynamic>(),
    );
  }

  Future<Uint8List> getPeriodProtocolFileBytes(String periodId) async {
    final r = await dio.get(
      '/periods/$periodId/protocol/file',
      options: Options(responseType: ResponseType.bytes),
    );

    final data = r.data;
    if (data is Uint8List) return data;
    if (data is List<int>) return Uint8List.fromList(data);
    if (data is List) {
      return Uint8List.fromList(data.cast<int>());
    }

    throw StateError('Unexpected PDF response type: ${data.runtimeType}');
  }

  Future<Uint8List> downloadPeriodProtocolBytes(String periodId) async {
    final r = await dio.get(
      '/periods/$periodId/protocol/download',
      options: Options(responseType: ResponseType.bytes),
    );

    final data = r.data;
    if (data is Uint8List) return data;
    if (data is List<int>) return Uint8List.fromList(data);
    if (data is List) {
      return Uint8List.fromList(data.cast<int>());
    }

    throw StateError('Unexpected PDF response type: ${data.runtimeType}');
  }

  Future<void> deletePeriodProtocol(String periodId) async {
    await dio.delete('/periods/$periodId/protocol');
  }

  // ----------------------------
  // EVENTS (swagger: /events, /events/{id})
  // ----------------------------

  Future<List<EventDto>> listEvents() async {
    final r = await dio.get('/events');
    final list = (r.data as List).cast<dynamic>();
    return list
        .map((e) => EventDto.fromJson((e as Map).cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<EventDto> getEvent(String id) async {
    final r = await dio.get('/events/$id');
    return EventDto.fromJson((r.data as Map).cast<String, dynamic>());
  }

  Future<EventDto> createEvent(CreateEventRequest req) async {
    final r = await dio.post('/events', data: req.toJson());
    return EventDto.fromJson((r.data as Map).cast<String, dynamic>());
  }

  Future<EventDto> updateEvent(String id, UpdateEventRequest req) async {
    final r = await dio.patch('/events/$id', data: req.toJson());
    return EventDto.fromJson((r.data as Map).cast<String, dynamic>());
  }

  Future<void> deleteEvent(String id) async {
    await dio.delete('/events/$id');
  }

  // ----------------------------
  // ATTENDANCE (swagger: /events/{eventId}/attendance, generate-fines)
  // ----------------------------

  Future<List<AttendanceDto>> listAttendance(String eventId) async {
    final r = await dio.get('/events/$eventId/attendance');
    final list = (r.data as List).cast<dynamic>();
    return list
        .map((e) => AttendanceDto.fromJson((e as Map).cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<AttendanceDto> upsertAttendance(
    String eventId,
    UpsertAttendanceRequest req,
  ) async {
    final r = await dio.put('/events/$eventId/attendance', data: req.toJson());
    return AttendanceDto.fromJson((r.data as Map).cast<String, dynamic>());
  }

  Future<void> deleteAttendance(String eventId, String userId) async {
    await dio.delete('/events/$eventId/attendance/$userId');
  }

  Future<GenerateAttendanceFinesResultDto> generateAttendanceFines(
    String eventId,
    GenerateAttendanceFinesRequest req,
  ) async {
    final r = await dio.post(
      '/events/$eventId/attendance/generate-fines',
      data: req.toJson(),
    );
    return GenerateAttendanceFinesResultDto.fromJson(
      (r.data as Map).cast<String, dynamic>(),
    );
  }

  // ----------------------------
  // ATTENDANCE FINES CONFIG (swagger: GET/PUT /attendance-fines)
  // ----------------------------

  Future<AttendanceFineConfigDto> getAttendanceFineConfig() async {
    final r = await dio.get('/attendance-fines');
    return AttendanceFineConfigDto.fromJson(
      (r.data as Map).cast<String, dynamic>(),
    );
  }

  Future<AttendanceFineConfigDto> setAttendanceFineConfig(
    SetAttendanceFineConfigRequest req,
  ) async {
    final r = await dio.put('/attendance-fines', data: req.toJson());
    return AttendanceFineConfigDto.fromJson(
      (r.data as Map).cast<String, dynamic>(),
    );
  }

  // ----------------------------
  // FINES (swagger: /fines, /fines/{id}, /fines/export.csv)
  // ----------------------------

  Future<List<FineDto>> listFines() async {
    final r = await dio.get('/fines');
    final list = (r.data as List).cast<dynamic>();
    return list
        .map((e) => FineDto.fromJson((e as Map).cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<FineDto> getFine(String id) async {
    final r = await dio.get('/fines/$id');
    return FineDto.fromJson((r.data as Map).cast<String, dynamic>());
  }

  Future<FineDto> createFine(CreateFineRequest req) async {
    final r = await dio.post('/fines', data: req.toJson());
    return FineDto.fromJson((r.data as Map).cast<String, dynamic>());
  }

  Future<FineDto> updateFine(String id, UpdateFineRequest req) async {
    final r = await dio.patch('/fines/$id', data: req.toJson());
    return FineDto.fromJson((r.data as Map).cast<String, dynamic>());
  }

  Future<void> deleteFine(String id) async {
    await dio.delete('/fines/$id');
  }

  /// NOTE: Swagger confirms this exists:
  /// GET /fines/export.csv
  /// Your controller path uses query params (periodId/includeDeleted) in your client.
  /// Keep it returning bytes.
  Future<Response<dynamic>> exportFinesCsv({
    String? periodId,
    bool includeDeleted = false,
  }) {
    return dio.get(
      '/fines/export.csv',
      queryParameters: {
        if (periodId != null && periodId.trim().isNotEmpty)
          'periodId': periodId.trim(),
        if (includeDeleted) 'includeDeleted': true,
      },
      options: Options(
        responseType: ResponseType.bytes,
        headers: const {'Accept': 'text/csv'},
      ),
    );
  }

  // ----------------------------
  // FINE PHOTOS (swagger: /fines/{fineId}/photos, /download)
  // ----------------------------

  Future<List<FinePhotoDto>> listFinePhotos(String fineId) async {
    final r = await dio.get('/fines/$fineId/photos');
    final list = (r.data as List).cast<dynamic>();
    return list
        .map((e) => FinePhotoDto.fromJson((e as Map).cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<FinePhotoDto> uploadFinePhoto({
    required String fineId,
    String? filePath, // native
    Uint8List? bytes, // web
    required String filename,
    String? contentType,
  }) async {
    if ((filePath == null && bytes == null) ||
        (filePath != null && bytes != null)) {
      throw ArgumentError('Provide exactly one of filePath or bytes.');
    }

    final MultipartFile mf = (bytes != null)
        ? MultipartFile.fromBytes(
            bytes,
            filename: filename,
            contentType: contentType == null
                ? null
                : MediaType.parse(contentType),
          )
        : await MultipartFile.fromFile(
            filePath!,
            filename: filename,
            contentType: contentType == null
                ? null
                : MediaType.parse(contentType),
          );

    final form = FormData.fromMap({'file': mf});

    final r = await dio.post(
      '/fines/$fineId/photos',
      data: form,
      // Dio sets boundary; specifying contentType explicitly is OK but not required.
      options: Options(contentType: 'multipart/form-data'),
    );

    return FinePhotoDto.fromJson((r.data as Map).cast<String, dynamic>());
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

  // ----------------------------
  // FINE CATALOG (swagger: /fine-catalog, /fine-catalog/{id})
  // ----------------------------

  Future<List<FineCatalogItemDto>> listFineCatalog({
    bool? active,
    bool? forCreation,
  }) async {
    final r = await dio.get(
      '/fine-catalog',
      queryParameters: {'active': ?active, 'forCreation': ?forCreation},
    );

    final list = (r.data as List).cast<dynamic>();
    return list
        .map(
          (e) =>
              FineCatalogItemDto.fromJson((e as Map).cast<String, dynamic>()),
        )
        .toList(growable: false);
  }

  Future<FineCatalogItemDto> createFineCatalogItem(
    CreateFineCatalogItemRequest req,
  ) async {
    final r = await dio.post('/fine-catalog', data: req.toJson());
    return FineCatalogItemDto.fromJson((r.data as Map).cast<String, dynamic>());
  }

  Future<FineCatalogItemDto> getFineCatalogItem(String id) async {
    final r = await dio.get('/fine-catalog/$id');
    return FineCatalogItemDto.fromJson((r.data as Map).cast<String, dynamic>());
  }

  Future<FineCatalogItemDto> updateFineCatalogItem(
    String id,
    UpdateFineCatalogItemRequest req,
  ) async {
    final r = await dio.patch('/fine-catalog/$id', data: req.toJson());
    return FineCatalogItemDto.fromJson((r.data as Map).cast<String, dynamic>());
  }

  Future<void> deleteFineCatalogItem(String id) async {
    await dio.delete('/fine-catalog/$id');
  }

  // ----------------------------
  // PAUKSTUNDEN
  // ----------------------------

  Future<PaukstundenEntryDto> createPaukstunde(
    CreatePaukstundeRequest req,
  ) async {
    final r = await dio.post('/paukstunden', data: req.toJson());
    return PaukstundenEntryDto.fromJson(
      (r.data as Map).cast<String, dynamic>(),
    );
  }

  Future<PaukstundenListDto> getMyCurrentPaukstunden() async {
    final r = await dio.get('/paukstunden/me/current-conventsperiode');
    return PaukstundenListDto.fromJson(r.data);
  }

  Future<PaukstundenListDto> getCurrentPaukstunden() async {
    final r = await dio.get('/paukstunden/current-conventsperiode');
    return PaukstundenListDto.fromJson(r.data);
  }

  Future<PaukstundenListDto> getUserCurrentPaukstunden(String userId) async {
    final r = await dio.get(
      '/paukstunden/users/$userId/current-conventsperiode',
    );
    return PaukstundenListDto.fromJson(r.data);
  }

  Future<PaukstundenSummaryDto> getCurrentPaukstundenSummary() async {
    final r = await dio.get('/paukstunden/summary/current-conventsperiode');
    return PaukstundenSummaryDto.fromJson(r.data);
  }

  Future<PaukstundenEntryDto> updatePaukstunde(
    String id,
    UpdatePaukstundeRequest req,
  ) async {
    final r = await dio.patch('/paukstunden/$id', data: req.toJson());
    return PaukstundenEntryDto.fromJson(
      (r.data as Map).cast<String, dynamic>(),
    );
  }

  Future<void> deletePaukstunde(String id) async {
    await dio.delete('/paukstunden/$id');
  }

  // ----------------------------
  // FINE SUGGESTIONS (swagger: /fine-suggestions, accept/reject)
  // ----------------------------

  Future<List<FineSuggestionDto>> listSuggestions({
    String? status,
    bool mine = false,
  }) async {
    final r = await dio.get(
      '/fine-suggestions',
      queryParameters: {
        if (status != null && status.trim().isNotEmpty) 'status': status.trim(),
        if (mine) 'mine': true,
      },
    );

    final list = (r.data as List).cast<dynamic>();
    return list
        .map(
          (e) => FineSuggestionDto.fromJson((e as Map).cast<String, dynamic>()),
        )
        .toList(growable: false);
  }

  Future<FineSuggestionDto> getSuggestion(String id) async {
    final r = await dio.get('/fine-suggestions/$id');
    return FineSuggestionDto.fromJson((r.data as Map).cast<String, dynamic>());
  }

  Future<FineSuggestionDto> createSuggestion(
    CreateFineSuggestionRequest req,
  ) async {
    final r = await dio.post('/fine-suggestions', data: req.toJson());
    return FineSuggestionDto.fromJson((r.data as Map).cast<String, dynamic>());
  }

  Future<FineSuggestionDto> updateSuggestion(
    String id,
    UpdateFineSuggestionRequest req,
  ) async {
    final r = await dio.patch('/fine-suggestions/$id', data: req.toJson());
    return FineSuggestionDto.fromJson((r.data as Map).cast<String, dynamic>());
  }

  Future<void> deleteSuggestion(String id) async {
    await dio.delete('/fine-suggestions/$id');
  }

  Future<void> rejectSuggestion(String id) async {
    await dio.post('/fine-suggestions/$id/reject');
  }

  Future<FineDtoAcceptResult> acceptSuggestion(String id) async {
    final r = await dio.post('/fine-suggestions/$id/accept');
    return FineDtoAcceptResult.fromJson(
      (r.data as Map).cast<String, dynamic>(),
    );
  }

  // ----------------------------
  // FINE SUGGESTION PHOTOS
  // ----------------------------

  Future<List<FineSuggestionPhotoDto>> listSuggestionPhotos(
    String suggestionId,
  ) async {
    final r = await dio.get('/fine-suggestions/$suggestionId/photos');
    final list = (r.data as List).cast<dynamic>();
    return list
        .map(
          (e) => FineSuggestionPhotoDto.fromJson(
            (e as Map).cast<String, dynamic>(),
          ),
        )
        .toList(growable: false);
  }

  Future<FineSuggestionPhotoDto> uploadSuggestionPhoto({
    required String suggestionId,
    String? filePath,
    Uint8List? bytes,
    required String filename,
    String? contentType,
  }) async {
    if ((filePath == null && bytes == null) ||
        (filePath != null && bytes != null)) {
      throw ArgumentError('Provide exactly one of filePath or bytes.');
    }

    final MultipartFile mf = (bytes != null)
        ? MultipartFile.fromBytes(
            bytes,
            filename: filename,
            contentType: contentType == null
                ? null
                : MediaType.parse(contentType),
          )
        : await MultipartFile.fromFile(
            filePath!,
            filename: filename,
            contentType: contentType == null
                ? null
                : MediaType.parse(contentType),
          );

    final form = FormData.fromMap({'file': mf});

    final r = await dio.post(
      '/fine-suggestions/$suggestionId/photos',
      data: form,
      options: Options(contentType: 'multipart/form-data'),
    );

    return FineSuggestionPhotoDto.fromJson(
      (r.data as Map).cast<String, dynamic>(),
    );
  }

  Future<Uint8List> downloadSuggestionPhotoBytes({
    required String suggestionId,
    required String photoId,
  }) async {
    final r = await dio.get(
      '/fine-suggestions/$suggestionId/photos/$photoId/download',
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList((r.data as List<int>));
  }

  Future<void> deleteSuggestionPhoto({
    required String suggestionId,
    required String photoId,
  }) async {
    await dio.delete('/fine-suggestions/$suggestionId/photos/$photoId');
  }

  // ----------------------------
  // TASKS (swagger: /tasks, /tasks/{id}, /tasks/{id}/solved, /admin/tasks, /tasks/solved)
  // ----------------------------

  Future<List<TaskDto>> listMyTasks() async {
    final r = await dio.get('/tasks');
    final list = (r.data as List).cast<dynamic>();
    return list
        .map((e) => TaskDto.fromJson((e as Map).cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<List<TaskDto>> listAdminTasks() async {
    final r = await dio.get('/admin/tasks');
    final list = (r.data as List).cast<dynamic>();
    return list
        .map((e) => TaskDto.fromJson((e as Map).cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<TaskDto> createTask(CreateTaskRequest req) async {
    final r = await dio.post('/tasks', data: req.toJson());
    return TaskDto.fromJson((r.data as Map).cast<String, dynamic>());
  }

  Future<TaskDto> updateTask(String taskId, UpdateTaskRequest req) async {
    final r = await dio.patch('/tasks/$taskId', data: req.toJson());
    return TaskDto.fromJson((r.data as Map).cast<String, dynamic>());
  }

  Future<TaskDto> setTaskSolved(String taskId, {required bool solved}) async {
    // swagger shows SetTaskSolvedRequest schema, but example is { solved: true }.
    final r = await dio.post('/tasks/$taskId/solved', data: {'solved': solved});
    return TaskDto.fromJson((r.data as Map).cast<String, dynamic>());
  }

  Future<void> deleteTask(String taskId) async {
    await dio.delete('/tasks/$taskId');
  }

  Future<void> deleteAllSolvedMyTasks() async {
    await dio.delete('/tasks/solved');
  }

  // ----------------------------
  // LIVE EVENTS (swagger: /live-events, /live-events/{id})
  // ----------------------------

  Future<List<LiveEventDto>> listLiveEvents() async {
    final r = await dio.get('/live-events');
    final list = (r.data as List).cast<dynamic>();
    return list
        .map((e) => LiveEventDto.fromJson((e as Map).cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<LiveEventDto> getLiveEvent(String id) async {
    final r = await dio.get('/live-events/$id');
    return LiveEventDto.fromJson((r.data as Map).cast<String, dynamic>());
  }

  Future<LiveEventDto> createLiveEvent(CreateLiveEventRequest req) async {
    final r = await dio.post('/live-events', data: req.toJson());
    return LiveEventDto.fromJson((r.data as Map).cast<String, dynamic>());
  }

  Future<LiveEventDto> updateLiveEvent(
    String id,
    UpdateLiveEventRequest req,
  ) async {
    final r = await dio.patch('/live-events/$id', data: req.toJson());
    return LiveEventDto.fromJson((r.data as Map).cast<String, dynamic>());
  }

  Future<void> deleteLiveEvent(String id) async {
    await dio.delete('/live-events/$id');
  }

  Future<LiveEventReactionToggleResult> toggleLiveEventReaction({
    required String liveEventId,
    required LiveEventReactionType type,
  }) async {
    final r = await dio.put(
      '/live-events/$liveEventId/reactions/${type.apiValue}',
    );
    final data = r.data;

    if (data is Map) {
      final json = data.cast<String, dynamic>();
      if (json.containsKey('title') || json.containsKey('expiresAt')) {
        return LiveEventReactionToggleResult(
          event: LiveEventDto.fromJson(json),
        );
      }
      if (json['reactions'] is Map) {
        return LiveEventReactionToggleResult(
          summary: LiveEventReactionSummary.fromJson(
            (json['reactions'] as Map).cast<String, dynamic>(),
          ),
        );
      }
      if (json.containsKey('prostCount') ||
          json.containsKey('ichKommeCount') ||
          json.containsKey('reactedProst') ||
          json.containsKey('reactedIchKomme')) {
        return LiveEventReactionToggleResult(
          summary: LiveEventReactionSummary.fromJson(json),
        );
      }
    }

    return LiveEventReactionToggleResult(
      event: await getLiveEvent(liveEventId),
    );
  }

  // ----------------------------
  // NOTIFICATIONS (swagger: /notifications, /notifications/unread-count, /notifications/{id}/read)
  // ----------------------------

  Future<List<NotificationDto>> listNotifications({int limit = 50}) async {
    final r = await dio.get(
      '/notifications',
      queryParameters: {'limit': limit},
    );
    final list = (r.data as List).cast<dynamic>();
    return list
        .map(
          (e) => NotificationDto.fromJson((e as Map).cast<String, dynamic>()),
        )
        .toList(growable: false);
  }

  Future<UnreadCountDto> getUnreadCount() async {
    final r = await dio.get('/notifications/unread-count');
    return UnreadCountDto.fromJson((r.data as Map).cast<String, dynamic>());
  }

  Future<void> markNotificationRead(String id) async {
    await dio.post('/notifications/$id/read');
  }

  Future<void> deleteNotification(String id) async {
    await dio.delete('/notifications/$id');
  }

  Future<void> clearNotifications() async {
    await dio.delete('/notifications');
  }

  // ----------------------------
  // PUSH (swagger: /push/register/webpush, /push/register/fcm)
  // ----------------------------

  Future<void> registerFcmToken(String token) async {
    await dio.post('/push/register/fcm', data: {'token': token});
  }

  Future<void> registerWebPush({
    required String endpoint,
    required String p256dh,
    required String auth,
    required Map<String, dynamic> raw,
  }) async {
    await dio.post(
      '/push/register/webpush',
      data: {
        'endpoint': endpoint,
        'keys': {'p256dh': p256dh, 'auth': auth},
        'raw': raw,
      },
    );
  }

  // ----------------------------
  // SESSIONS
  // ----------------------------

  Future<List<UserSessionDto>> listMySessions() async {
    final r = await dio.get('/sessions/me');
    final list = (r.data as List).cast<dynamic>();
    return list
        .map((e) => UserSessionDto.fromJson((e as Map).cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<void> touchMySession() async {
    await dio.post(
      '/sessions/me/touch',
      data: await collectDeviceInfoPayload(),
    );
  }

  Future<void> revokeMySession(String sessionId) async {
    await dio.delete('/sessions/me/$sessionId');
  }

  Future<SessionStatsDto> getSessionStats() async {
    final r = await dio.get('/sessions/admin/stats');
    return SessionStatsDto.fromJson((r.data as Map).cast<String, dynamic>());
  }

  Future<List<UserSessionDto>> listAdminSessions() async {
    final r = await dio.get('/sessions/admin');
    final list = (r.data as List).cast<dynamic>();
    return list
        .map((e) => UserSessionDto.fromJson((e as Map).cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<void> revokeAdminSession(String sessionId) async {
    await dio.delete('/sessions/admin/$sessionId');
  }

  // ----------------------------
  // ATTENDANCE: swagger includes DELETE returning 200 (no body). Keep void.
  // ----------------------------
}
