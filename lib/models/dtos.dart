class TokenResponse {
  final String accessToken;
  final String refreshToken;

  TokenResponse({required this.accessToken, required this.refreshToken});

  factory TokenResponse.fromJson(Map<String, dynamic> json) => TokenResponse(
    accessToken: json['accessToken'] as String,
    refreshToken: json['refreshToken'] as String,
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
    id: json['id'] as String,
    semester: json['semester'] as String,
    startAt: json['startAt'] as String,
    endAt: json['endAt'] as String,
    active: (json['active'] as bool?) ?? false,
    locked: (json['locked'] as bool?) ?? false,
  );
}

class UserBalanceDto {
  final String userId;
  final int balanceCents;
  final String balanceFormatted;

  UserBalanceDto({
    required this.userId,
    required this.balanceCents,
    required this.balanceFormatted,
  });

  factory UserBalanceDto.fromJson(Map<String, dynamic> json) => UserBalanceDto(
    userId: json['userId'] as String,
    balanceCents: (json['balanceCents'] as num).toInt(),
    balanceFormatted: json['balanceFormatted'] as String,
  );
}

class LiveEventDto {
  final String id;
  final String title;
  final String place;
  final String description;
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
    id: json['id'] as String,
    title: json['title'] as String,
    place: json['place'] as String,
    description: json['description'] as String,
    createdByUserId: json['createdByUserId'] as String,
    createdAt: json['createdAt'] as String,
    expiresAt: json['expiresAt'] as String,
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
    id: json['id'] as String,
    username: json['username'] as String,
    displayName: json['displayName'] as String,
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
    id: json['id'] as String,
    username: json['username'] as String,
    displayName: json['displayName'] as String,
    disabled: (json['disabled'] as bool?) ?? false,
    roles: (json['roles'] as List?)?.map((e) => e.toString()).toList() ?? const [],
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
    id: json['id'] as String,
    title: json['title'] as String,
    defaultAmountCents: (json['defaultAmountCents'] == null)
        ? null
        : (json['defaultAmountCents'] as num).toInt(),
    active: (json['active'] as bool?) ?? true,
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
  final String periodId;
  final String creatorUserId;
  final String? catalogItemId;
  final String? reason; // IMPORTANT: reason is now used for BOTH catalog + custom
  final int? amountCents;
  final FineType type;
  final List<String> targetUserIds;
  final String createdAt;

  final String? suggesterUserId;
  final String? acceptedFromSuggestionId;

  FineDto({
    required this.id,
    required this.periodId,
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
    id: json['id'] as String,
    periodId: json['periodId'] as String,
    creatorUserId: json['creatorUserId'] as String,
    catalogItemId: json['catalogItemId'] as String?,
    reason: json['reason'] as String?,
    amountCents: json['amountCents'] == null ? null : (json['amountCents'] as num).toInt(),
    type: _fineTypeFromJson(json['type'] as String),
    targetUserIds: (json['targetUserIds'] as List).map((e) => e as String).toList(),
    createdAt: json['createdAt'] as String,
    suggesterUserId: json['suggesterUserId'] as String?,
    acceptedFromSuggestionId: json['acceptedFromSuggestionId'] as String?,
  );
}

class CreateFineRequest {
  final String periodId;
  final List<String> targetUserIds;
  final String? catalogItemId;
  final String reason; // REQUIRED for both catalog + custom
  final int amountCents;

  CreateFineRequest({
    required this.periodId,
    required this.targetUserIds,
    this.catalogItemId,
    required this.reason,
    required this.amountCents,
  });

  Map<String, dynamic> toJson() => {
    'periodId': periodId,
    'targetUserIds': targetUserIds,
    if (catalogItemId != null) 'catalogItemId': catalogItemId,
    'reason': reason,
    'amountCents': amountCents,
  };
}

// ---------- Fine Suggestions ----------
class FineSuggestionDto {
  final String id;
  final String periodId;
  final String creatorUserId;
  final String? catalogItemId;
  final String? reason; // required by UI, backend may still store nullable
  final int? amountCents;
  final FineType type;
  final String status; // PENDING/ACCEPTED/REJECTED
  final List<String> targetUserIds;
  final String createdAt;

  FineSuggestionDto({
    required this.id,
    required this.periodId,
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
    id: json['id'] as String,
    periodId: json['periodId'] as String,
    creatorUserId: json['creatorUserId'] as String,
    catalogItemId: json['catalogItemId'] as String?,
    reason: json['reason'] as String?,
    amountCents: json['amountCents'] == null ? null : (json['amountCents'] as num).toInt(),
    type: _fineTypeFromJson(json['type'] as String),
    status: json['status'] as String,
    targetUserIds: (json['targetUserIds'] as List).map((e) => e as String).toList(),
    createdAt: json['createdAt'] as String,
  );
}

class CreateFineSuggestionRequest {
  final String periodId;
  final List<String> targetUserIds;
  final String? catalogItemId;
  final String reason; // REQUIRED for both catalog + custom
  final int amountCents;

  CreateFineSuggestionRequest({
    required this.periodId,
    required this.targetUserIds,
    this.catalogItemId,
    required this.reason,
    required this.amountCents,
  });

  Map<String, dynamic> toJson() => {
    'periodId': periodId,
    'targetUserIds': targetUserIds,
    if (catalogItemId != null) 'catalogItemId': catalogItemId,
    'reason': reason,
    'amountCents': amountCents,
  };
}

// ---------- Update Fine ----------
class UpdateFineRequest {
  final List<String>? targetUserIds;
  final String? catalogItemId;
  final String? reason;
  final int? amountCents;

  UpdateFineRequest({
    this.targetUserIds,
    this.catalogItemId,
    this.reason,
    this.amountCents,
  });

  Map<String, dynamic> toJson() => {
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
    fineId: json['fineId'] as String?,
    fine: (json['fine'] is Map<String, dynamic>) ? FineDto.fromJson(json['fine'] as Map<String, dynamic>) : null,
  );
}

// ---------- Scheduled Events ----------
enum EventOwnerType { senior, housekeeping }

EventOwnerType _eventOwnerTypeFromJson(String s) =>
    (s == 'SENIOR') ? EventOwnerType.senior : EventOwnerType.housekeeping;

class EventDto {
  final String id;
  final String periodId;
  final String creatorUserId;
  final String title;
  final String startsAt;
  final bool mandatory;
  final EventOwnerType ownerType;
  final String createdAt;

  EventDto({
    required this.id,
    required this.periodId,
    required this.creatorUserId,
    required this.title,
    required this.startsAt,
    required this.mandatory,
    required this.ownerType,
    required this.createdAt,
  });

  factory EventDto.fromJson(Map<String, dynamic> json) => EventDto(
    id: json['id'] as String,
    periodId: json['periodId'] as String,
    creatorUserId: json['creatorUserId'] as String,
    title: json['title'] as String,
    startsAt: json['startsAt'] as String,
    mandatory: (json['mandatory'] as bool?) ?? false,
    ownerType: _eventOwnerTypeFromJson(json['ownerType'] as String),
    createdAt: json['createdAt'] as String,
  );
}

class CreateEventRequest {
  final String periodId;
  final String title;
  final String startsAt; // ISO string
  final bool mandatory;

  CreateEventRequest({
    required this.periodId,
    required this.title,
    required this.startsAt,
    required this.mandatory,
  });

  Map<String, dynamic> toJson() => {
    'periodId': periodId,
    'title': title,
    'startsAt': startsAt,
    'mandatory': mandatory,
  };
}

class UpdateEventRequest {
  final String? periodId;
  final String? title;
  final String? startsAt; // ISO string
  final bool? mandatory;

  UpdateEventRequest({
    this.periodId,
    this.title,
    this.startsAt,
    this.mandatory,
  });

  Map<String, dynamic> toJson() => {
    if (periodId != null) 'periodId': periodId,
    if (title != null) 'title': title,
    if (startsAt != null) 'startsAt': startsAt,
    if (mandatory != null) 'mandatory': mandatory,
  };
}

// ---------- Attendance ----------
enum AttendanceStatus { late, absent }

AttendanceStatus _attendanceStatusFromJson(String s) =>
    (s == 'ABSENT') ? AttendanceStatus.absent : AttendanceStatus.late;

String _attendanceStatusToJson(AttendanceStatus s) =>
    (s == AttendanceStatus.absent) ? 'ABSENT' : 'LATE';

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
    id: json['id'] as String,
    eventId: json['eventId'] as String,
    periodId: json['periodId'] as String,
    userId: json['userId'] as String,
    status: _attendanceStatusFromJson(json['status'] as String),
    lateMinutes: json['lateMinutes'] == null ? null : (json['lateMinutes'] as num).toInt(),
    fineId: json['fineId'] as String?,
    createdAt: json['createdAt'] as String,
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
  final String startAt; // ISO date-time
  final String endAt;   // ISO date-time

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
  final String? startAt; // ISO date-time
  final String? endAt;   // ISO date-time
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

