// ---- tiny JSON helpers (robust against null + wrong types) ----
String _reqString(Map<String, dynamic> j, String k) => (j[k] ?? '').toString();

String? _optString(Map<String, dynamic> j, String k) {
  final v = j[k];
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

int _optInt(Map<String, dynamic> j, String k, {int fallback = 0}) {
  final v = j[k];
  if (v == null) return fallback;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? fallback;
}

bool _optBool(Map<String, dynamic> j, String k, {bool fallback = false}) {
  final v = j[k];
  if (v is bool) return v;
  if (v == null) return fallback;
  final s = v.toString().toLowerCase();
  if (s == 'true') return true;
  if (s == 'false') return false;
  return fallback;
}

List<String> _optStringList(Map<String, dynamic> j, String k) {
  final v = j[k];
  if (v is List) return v.map((e) => e.toString()).toList();
  return const [];
}

DateTime? _optDateTime(Map<String, dynamic> j, String k) {
  final s = _optString(j, k);
  if (s == null) return null;
  return DateTime.tryParse(s);
}

DateTime _reqDateTime(Map<String, dynamic> j, String k) {
  final s = _reqString(j, k);
  return DateTime.parse(s);
}

// ---------------- DTOs ----------------

class TokenResponse {
  final String accessToken;
  final String refreshToken;

  TokenResponse({required this.accessToken, required this.refreshToken});

  factory TokenResponse.fromJson(Map<String, dynamic> json) => TokenResponse(
    accessToken: _reqString(json, 'accessToken'),
    refreshToken: _reqString(json, 'refreshToken'),
  );
}

class ConventPeriodDto {
  final String id;
  final String semester;
  final String startAt;
  final String endAt;
  final bool active;
  final bool locked;

  ConventPeriodDto({
    required this.id,
    required this.semester,
    required this.startAt,
    required this.endAt,
    required this.active,
    required this.locked,
  });

  factory ConventPeriodDto.fromJson(Map<String, dynamic> json) => ConventPeriodDto(
    id: _reqString(json, 'id'),
    semester: _reqString(json, 'semester'),
    startAt: _reqString(json, 'startAt'),
    endAt: _reqString(json, 'endAt'),
    active: _optBool(json, 'active', fallback: false),
    locked: _optBool(json, 'locked', fallback: false),
  );
}

class UserBalanceDto {
  final String userId;
  final int balanceCents;

  /// Backend liefert hier oft null -> deswegen nullable
  final String? balanceFormatted;

  UserBalanceDto({
    required this.userId,
    required this.balanceCents,
    required this.balanceFormatted,
  });

  factory UserBalanceDto.fromJson(Map<String, dynamic> json) => UserBalanceDto(
    userId: _reqString(json, 'userId'),
    balanceCents: _optInt(json, 'balanceCents', fallback: 0),
    balanceFormatted: _optString(json, 'balanceFormatted'),
  );
}

class LiveEventDto {
  final String id;
  final String title;

  /// place/description können realistisch null sein -> nullable machen
  final String? place;
  final String? description;

  final String createdByUserId;
  final String createdAt;
  final String expiresAt;

  LiveEventDto({
    required this.id,
    required this.title,
    required this.place,
    required this.description,
    required this.createdByUserId,
    required this.createdAt,
    required this.expiresAt,
  });

  factory LiveEventDto.fromJson(Map<String, dynamic> json) => LiveEventDto(
    id: _reqString(json, 'id'),
    title: _reqString(json, 'title'),
    place: _optString(json, 'place'),
    description: _optString(json, 'description'),
    createdByUserId: _reqString(json, 'createdByUserId'),
    createdAt: _reqString(json, 'createdAt'),
    expiresAt: _reqString(json, 'expiresAt'),
  );
}

// ---------- Users (Picker) ----------
class UserPickerDto {
  final String id;
  final String username;
  final String displayName;

  UserPickerDto({
    required this.id,
    required this.username,
    required this.displayName,
  });

  factory UserPickerDto.fromJson(Map<String, dynamic> json) => UserPickerDto(
    id: _reqString(json, 'id'),
    username: _reqString(json, 'username'),
    displayName: _reqString(json, 'displayName'),
  );
}

class UserDto {
  final String id;
  final String username;
  final String displayName;
  final bool disabled;
  final List<String> roles;

  UserDto({
    required this.id,
    required this.username,
    required this.displayName,
    required this.disabled,
    required this.roles,
  });

  factory UserDto.fromJson(Map<String, dynamic> json) => UserDto(
    id: _reqString(json, 'id'),
    username: _reqString(json, 'username'),
    displayName: _reqString(json, 'displayName'),
    disabled: _optBool(json, 'disabled', fallback: false),
    roles: _optStringList(json, 'roles'),
  );
}

class CreateUserRequest {
  final String username;
  final String displayName;
  final String password;
  final List<String> roles;

  CreateUserRequest({
    required this.username,
    required this.displayName,
    required this.password,
    required this.roles,
  });

  Map<String, dynamic> toJson() => {
    'username': username,
    'displayName': displayName,
    'password': password,
    'roles': roles,
  };
}

class UpdateUserRequest {
  final String? displayName;
  final bool? disabled;
  final List<String>? roles;

  UpdateUserRequest({this.displayName, this.disabled, this.roles});

  Map<String, dynamic> toJson() => {
    if (displayName != null) 'displayName': displayName,
    if (disabled != null) 'disabled': disabled,
    if (roles != null) 'roles': roles,
  };
}

// ---------- TASKS ----------
class TaskDto {
  final String id;
  final String creatorUserId;
  final String title;
  final String description;
  final bool solved;
  final String? solvedAt;
  final List<UserPickerDto> assignees;
  final String createdAt;

  TaskDto({
    required this.id,
    required this.creatorUserId,
    required this.title,
    required this.description,
    required this.solved,
    required this.solvedAt,
    required this.assignees,
    required this.createdAt,
  });

  factory TaskDto.fromJson(Map<String, dynamic> json) => TaskDto(
    id: _reqString(json, 'id'),
    creatorUserId: _reqString(json, 'creatorUserId'),
    title: _reqString(json, 'title'),
    description: _reqString(json, 'description'),
    solved: _optBool(json, 'solved', fallback: false),
    solvedAt: _optString(json, 'solvedAt'),
    assignees: (json['assignees'] is List)
        ? (json['assignees'] as List)
        .whereType<Map>()
        .map((m) => UserPickerDto.fromJson(m.cast<String, dynamic>()))
        .toList(growable: false)
        : const <UserPickerDto>[],
    createdAt: _reqString(json, 'createdAt'),
  );
}

class CreateTaskRequest {
  final String title;
  final String description;
  final List<String> assigneeUserIds;

  CreateTaskRequest({
    required this.title,
    required this.description,
    required this.assigneeUserIds,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
    'assigneeUserIds': assigneeUserIds,
  };
}

class UpdateTaskRequest {
  final String? title;
  final String? description;
  final List<String>? assigneeUserIds;

  UpdateTaskRequest({
    this.title,
    this.description,
    this.assigneeUserIds,
  });

  Map<String, dynamic> toJson() => {
    if (title != null) 'title': title,
    if (description != null) 'description': description,
    if (assigneeUserIds != null) 'assigneeUserIds': assigneeUserIds,
  };
}

// ---------- Fine Catalog ----------
class FineCatalogItemDto {
  final String id;
  final String title;
  final int? defaultAmountCents;
  final bool active;

  FineCatalogItemDto({
    required this.id,
    required this.title,
    required this.defaultAmountCents,
    required this.active,
  });

  factory FineCatalogItemDto.fromJson(Map<String, dynamic> json) => FineCatalogItemDto(
    id: _reqString(json, 'id'),
    title: _reqString(json, 'title'),
    defaultAmountCents: json['defaultAmountCents'] == null ? null : _optInt(json, 'defaultAmountCents'),
    active: _optBool(json, 'active', fallback: true),
  );
}

class CreateFineCatalogItemRequest {
  final String title;
  final int? defaultAmountCents;
  final bool active;

  CreateFineCatalogItemRequest({
    required this.title,
    this.defaultAmountCents,
    this.active = true,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    if (defaultAmountCents != null) 'defaultAmountCents': defaultAmountCents,
    'active': active,
  };
}

class UpdateFineCatalogItemRequest {
  final String? title;
  final int? defaultAmountCents;
  final bool? active;

  UpdateFineCatalogItemRequest({this.title, this.defaultAmountCents, this.active});

  Map<String, dynamic> toJson() => {
    if (title != null) 'title': title,
    if (defaultAmountCents != null) 'defaultAmountCents': defaultAmountCents,
    if (active != null) 'active': active,
  };
}

// ---------- Fines ----------
enum FineType { catalog, custom }

FineType _fineTypeFromJson(String s) => (s == 'CATALOG') ? FineType.catalog : FineType.custom;

class FineDto {
  final String id;

  /// date-only: YYYY-MM-DD
  final String fineDate;

  final String creatorUserId;
  final String? catalogItemId;
  final String? reason;
  final int? amountCents;
  final FineType type;
  final List<String> targetUserIds;

  /// date-time
  final String createdAt;

  final String? suggesterUserId;
  final String? acceptedFromSuggestionId;

  FineDto({
    required this.id,
    required this.fineDate,
    required this.creatorUserId,
    required this.catalogItemId,
    required this.reason,
    required this.amountCents,
    required this.type,
    required this.targetUserIds,
    required this.createdAt,
    required this.suggesterUserId,
    required this.acceptedFromSuggestionId,
  });

  factory FineDto.fromJson(Map<String, dynamic> json) => FineDto(
    id: _reqString(json, 'id'),
    fineDate: _reqString(json, 'fineDate'),
    creatorUserId: _reqString(json, 'creatorUserId'),
    catalogItemId: _optString(json, 'catalogItemId'),
    reason: _optString(json, 'reason'),
    amountCents: json['amountCents'] == null ? null : _optInt(json, 'amountCents'),
    type: _fineTypeFromJson(_reqString(json, 'type')),
    targetUserIds: _optStringList(json, 'targetUserIds'),
    createdAt: _reqString(json, 'createdAt'),
    suggesterUserId: _optString(json, 'suggesterUserId'),
    acceptedFromSuggestionId: _optString(json, 'acceptedFromSuggestionId'),
  );
}

class FinePhotoDto {
  final String id;
  final String fineId;
  final String originalFilename;
  final String contentType;
  final int sizeBytes;
  final String createdAt;

  // optional (backend can add this later)
  final String? uploaderUserId;

  FinePhotoDto({
    required this.id,
    required this.fineId,
    required this.originalFilename,
    required this.contentType,
    required this.sizeBytes,
    required this.createdAt,
    required this.uploaderUserId,
  });

  factory FinePhotoDto.fromJson(Map<String, dynamic> json) => FinePhotoDto(
    id: (json['id'] as String?) ?? '',
    fineId: (json['fineId'] as String?) ?? '',
    originalFilename: (json['originalFilename'] as String?) ?? '',
    contentType: (json['contentType'] as String?) ?? '',
    sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
    createdAt: (json['createdAt'] as String?) ?? '',
    uploaderUserId: (json['uploaderUserId'] as String?),
  );
}

class CreateFineRequest {
  /// date-only: YYYY-MM-DD
  final String fineDate;

  final List<String> targetUserIds;
  final String? catalogItemId;
  final String? reason;
  final int? amountCents;

  CreateFineRequest({
    required this.fineDate,
    required this.targetUserIds,
    this.catalogItemId,
    this.reason,
    this.amountCents,
  });

  Map<String, dynamic> toJson() => {
    'fineDate': fineDate,
    'targetUserIds': targetUserIds,
    if (catalogItemId != null) 'catalogItemId': catalogItemId,
    if (reason != null) 'reason': reason,
    if (amountCents != null) 'amountCents': amountCents,
  };
}

class QuoteDto {
  final String text;
  final String? author;

  QuoteDto({required this.text, this.author});

  factory QuoteDto.fromJson(Map<String, dynamic> json) => QuoteDto(
    text: _reqString(json, 'text').trim(),
    author: _optString(json, 'author')?.trim(),
  );

  Map<String, dynamic> toJson() => {
    'text': text,
    'author': author,
  };
}

// ---------- Fine Suggestions ----------
class FineSuggestionDto {
  final String id;
  final String fineDate;
  final String creatorUserId;
  final String? catalogItemId;
  final String? reason;
  final int? amountCents;
  final FineType type;
  final String status;
  final List<String> targetUserIds;
  final String createdAt;

  FineSuggestionDto({
    required this.id,
    required this.fineDate,
    required this.creatorUserId,
    required this.catalogItemId,
    required this.reason,
    required this.amountCents,
    required this.type,
    required this.status,
    required this.targetUserIds,
    required this.createdAt,
  });

  factory FineSuggestionDto.fromJson(Map<String, dynamic> json) => FineSuggestionDto(
    id: _reqString(json, 'id'),
    fineDate: _reqString(json, 'fineDate'),
    creatorUserId: _reqString(json, 'creatorUserId'),
    catalogItemId: _optString(json, 'catalogItemId'),
    reason: _optString(json, 'reason'),
    amountCents: json['amountCents'] == null ? null : _optInt(json, 'amountCents'),
    type: _fineTypeFromJson(_reqString(json, 'type')),
    status: _reqString(json, 'status'),
    targetUserIds: _optStringList(json, 'targetUserIds'),
    createdAt: _reqString(json, 'createdAt'),
  );
}

class CreateFineSuggestionRequest {
  final String fineDate;
  final List<String> targetUserIds;
  final String? catalogItemId;
  final String reason;
  final int amountCents;

  CreateFineSuggestionRequest({
    required this.fineDate,
    required this.targetUserIds,
    this.catalogItemId,
    required this.reason,
    required this.amountCents,
  });

  Map<String, dynamic> toJson() => {
    'fineDate': fineDate,
    'targetUserIds': targetUserIds,
    if (catalogItemId != null) 'catalogItemId': catalogItemId,
    'reason': reason,
    'amountCents': amountCents,
  };
}

// ---------- Update Fine ----------
class UpdateFineRequest {
  final String? fineDate;
  final List<String>? targetUserIds;
  final String? catalogItemId;
  final String? reason;
  final int? amountCents;

  UpdateFineRequest({
    this.fineDate,
    this.targetUserIds,
    this.catalogItemId,
    this.reason,
    this.amountCents,
  });

  Map<String, dynamic> toJson() => {
    if (fineDate != null) 'fineDate': fineDate,
    if (targetUserIds != null) 'targetUserIds': targetUserIds,
    if (catalogItemId != null) 'catalogItemId': catalogItemId,
    if (reason != null) 'reason': reason,
    if (amountCents != null) 'amountCents': amountCents,
  };
}

// ---------- Accept Fine Suggestion Result ----------
class FineDtoAcceptResult {
  final String? fineId;
  final FineDto? fine;

  FineDtoAcceptResult({this.fineId, this.fine});

  factory FineDtoAcceptResult.fromJson(Map<String, dynamic> json) => FineDtoAcceptResult(
    fineId: _optString(json, 'fineId'),
    fine: (json['fine'] is Map<String, dynamic>) ? FineDto.fromJson(json['fine'] as Map<String, dynamic>) : null,
  );
}

// ---------- Scheduled Events ----------
enum EventOwnerType { senior, housekeeping }

EventOwnerType _eventOwnerTypeFromJson(String s) => (s == 'SENIOR') ? EventOwnerType.senior : EventOwnerType.housekeeping;

class EventDto {
  final String id;
  final String creatorUserId;
  final String title;
  final String startsAt;
  final bool mandatory;
  final EventOwnerType ownerType;
  final String createdAt;

  EventDto({
    required this.id,
    required this.creatorUserId,
    required this.title,
    required this.startsAt,
    required this.mandatory,
    required this.ownerType,
    required this.createdAt,
  });

  factory EventDto.fromJson(Map<String, dynamic> json) => EventDto(
    id: _reqString(json, 'id'),
    creatorUserId: _reqString(json, 'creatorUserId'),
    title: _reqString(json, 'title'),
    startsAt: _reqString(json, 'startsAt'),
    mandatory: _optBool(json, 'mandatory', fallback: false),
    ownerType: _eventOwnerTypeFromJson(_reqString(json, 'ownerType')),
    createdAt: _reqString(json, 'createdAt'),
  );
}

class CreateEventRequest {
  final String title;
  final String startsAt;
  final bool mandatory;

  CreateEventRequest({
    required this.title,
    required this.startsAt,
    required this.mandatory,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'startsAt': startsAt,
    'mandatory': mandatory,
  };
}

class UpdateEventRequest {
  final String? title;
  final String? startsAt;
  final bool? mandatory;

  UpdateEventRequest({
    this.title,
    this.startsAt,
    this.mandatory,
  });

  Map<String, dynamic> toJson() => {
    if (title != null) 'title': title,
    if (startsAt != null) 'startsAt': startsAt,
    if (mandatory != null) 'mandatory': mandatory,
  };
}

// ---------- Attendance ----------
enum AttendanceStatus { late, absent }

AttendanceStatus _attendanceStatusFromJson(String s) => (s == 'ABSENT') ? AttendanceStatus.absent : AttendanceStatus.late;

String _attendanceStatusToJson(AttendanceStatus s) => (s == AttendanceStatus.absent) ? 'ABSENT' : 'LATE';

class AttendanceDto {
  final String id;
  final String eventId;
  final String periodId;
  final String userId;
  final AttendanceStatus status;
  final int? lateMinutes;
  final String? fineId;
  final String createdAt;

  AttendanceDto({
    required this.id,
    required this.eventId,
    required this.periodId,
    required this.userId,
    required this.status,
    required this.lateMinutes,
    required this.fineId,
    required this.createdAt,
  });

  factory AttendanceDto.fromJson(Map<String, dynamic> json) => AttendanceDto(
    id: _reqString(json, 'id'),
    eventId: _reqString(json, 'eventId'),
    periodId: _reqString(json, 'periodId'),
    userId: _reqString(json, 'userId'),
    status: _attendanceStatusFromJson(_reqString(json, 'status')),
    lateMinutes: json['lateMinutes'] == null ? null : _optInt(json, 'lateMinutes'),
    fineId: _optString(json, 'fineId'),
    createdAt: _reqString(json, 'createdAt'),
  );
}

class UpsertAttendanceRequest {
  final String userId;
  final AttendanceStatus status;
  final int? lateMinutes;

  UpsertAttendanceRequest({
    required this.userId,
    required this.status,
    this.lateMinutes,
  });

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'status': _attendanceStatusToJson(status),
    if (lateMinutes != null) 'lateMinutes': lateMinutes,
  };
}

class AttendanceFineConfigDto {
  final String? periodId;

  final String? lateCatalogItemId;
  final String? lateReason;
  final int lateAmountCents;

  final String? absentCatalogItemId;
  final String? absentReason;
  final int absentAmountCents;

  AttendanceFineConfigDto({
    required this.periodId,
    required this.lateCatalogItemId,
    required this.lateReason,
    required this.lateAmountCents,
    required this.absentCatalogItemId,
    required this.absentReason,
    required this.absentAmountCents,
  });

  factory AttendanceFineConfigDto.fromJson(Map<String, dynamic> json) => AttendanceFineConfigDto(
    periodId: _optString(json, 'periodId'),
    lateCatalogItemId: _optString(json, 'lateCatalogItemId'),
    lateReason: _optString(json, 'lateReason'),
    lateAmountCents: _optInt(json, 'lateAmountCents', fallback: 0),
    absentCatalogItemId: _optString(json, 'absentCatalogItemId'),
    absentReason: _optString(json, 'absentReason'),
    absentAmountCents: _optInt(json, 'absentAmountCents', fallback: 0),
  );
}

// ---------- Live Events ----------
class CreateLiveEventRequest {
  final String title;
  final String place;
  final String description;

  CreateLiveEventRequest({
    required this.title,
    required this.place,
    required this.description,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'place': place,
    'description': description,
  };
}

class UpdateLiveEventRequest {
  final String? title;
  final String? place;
  final String? description;

  UpdateLiveEventRequest({
    this.title,
    this.place,
    this.description,
  });

  Map<String, dynamic> toJson() => {
    if (title != null) 'title': title,
    if (place != null) 'place': place,
    if (description != null) 'description': description,
  };
}

class CreateConventPeriodRequest {
  final String semester;
  final String startAt;
  final String endAt;

  CreateConventPeriodRequest({
    required this.semester,
    required this.startAt,
    required this.endAt,
  });

  Map<String, dynamic> toJson() => {
    'semester': semester,
    'startAt': startAt,
    'endAt': endAt,
  };
}

class UpdateConventPeriodRequest {
  final String? semester;
  final String? startAt;
  final String? endAt;
  final bool? active;
  final bool? locked;

  UpdateConventPeriodRequest({
    this.semester,
    this.startAt,
    this.endAt,
    this.active,
    this.locked,
  });

  Map<String, dynamic> toJson() => {
    if (semester != null) 'semester': semester,
    if (startAt != null) 'startAt': startAt,
    if (endAt != null) 'endAt': endAt,
    if (active != null) 'active': active,
    if (locked != null) 'locked': locked,
  };
}

// ---------- Notifications ----------
class NotificationDto {
  final String id;
  final String userId;
  final String type;
  final String title;
  final String body;
  final Map<String, String> data;
  final DateTime createdAt;
  final DateTime? readAt;

  NotificationDto({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    required this.data,
    required this.createdAt,
    required this.readAt,
  });

  factory NotificationDto.fromJson(Map<String, dynamic> json) {
    final rawData = (json['data'] is Map) ? (json['data'] as Map).cast<String, dynamic>() : <String, dynamic>{};
    final data = <String, String>{};
    for (final e in rawData.entries) {
      final v = e.value;
      if (v == null) continue;
      data[e.key] = v.toString();
    }

    return NotificationDto(
      id: _reqString(json, 'id'),
      userId: _reqString(json, 'userId'),
      type: _reqString(json, 'type'),
      title: _reqString(json, 'title'),
      body: _reqString(json, 'body'),
      data: data,
      createdAt: _reqDateTime(json, 'createdAt'),
      readAt: _optDateTime(json, 'readAt'),
    );
  }

  NotificationDto copyWith({
    DateTime? readAt,
  }) {
    return NotificationDto(
      id: id,
      userId: userId,
      type: type,
      title: title,
      body: body,
      data: data,
      createdAt: createdAt,
      readAt: readAt ?? this.readAt,
    );
  }
}

class UnreadCountDto {
  final int unread;

  UnreadCountDto({required this.unread});

  factory UnreadCountDto.fromJson(Map<String, dynamic> json) => UnreadCountDto(
    unread: _optInt(json, 'unread', fallback: 0),
  );
}
