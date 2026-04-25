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

List<Map<String, dynamic>> _optList(Map<String, dynamic> j, String k) {
  final v = j[k];
  if (v is List) {
    return v
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList(growable: false);
  }
  return const <Map<String, dynamic>>[];
}

DateTime? _optDateTime(Map<String, dynamic> j, String k) {
  final s = _optString(j, k);
  if (s == null) return null;
  return DateTime.tryParse(s);
}

DateTime _reqDateTime(Map<String, dynamic> j, String k) {
  final s = _reqString(j, k).trim();
  final dt = DateTime.tryParse(s);
  if (dt != null) return dt;
  throw FormatException('Invalid datetime for "$k": "$s"');
}

DateTime _optDateTimeOrEpoch(Map<String, dynamic> j, String k) {
  final dt = _optDateTime(j, k);
  return dt ?? DateTime.fromMillisecondsSinceEpoch(0);
}

// ---- date-only helpers (YYYY-MM-DD) ----
// IMPORTANT: Do NOT DateTime.parse("YYYY-MM-DD").toLocal() because that can shift the day.
// Treat backend date-only values as a LocalDate, i.e. local midnight.

DateTime _parseLocalDate(String s) {
  // Expected: YYYY-MM-DD (backend sends DATE-only)
  // We construct a *local* DateTime at midnight to avoid timezone shifts.
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s.trim());
  if (m == null) return DateTime.fromMillisecondsSinceEpoch(0);

  final y = int.tryParse(m.group(1)!) ?? 1970;
  final mo = int.tryParse(m.group(2)!) ?? 1;
  final d = int.tryParse(m.group(3)!) ?? 1;
  return DateTime(y, mo, d); // local midnight
}

// ---------------- DTOs ----------------

class TokenResponse {
  final String accessToken;
  final String refreshToken;
  final String? sessionId;

  TokenResponse({
    required this.accessToken,
    required this.refreshToken,
    this.sessionId,
  });

  factory TokenResponse.fromJson(Map<String, dynamic> json) => TokenResponse(
    accessToken: _reqString(json, 'accessToken'),
    refreshToken: _reqString(json, 'refreshToken'),
    sessionId: _optString(json, 'sessionId'),
  );
}

class ConventPeriodDto {
  final String id;
  final String semester;

  /// date-only: YYYY-MM-DD
  final String startAt;

  /// date-only: YYYY-MM-DD
  final String endAt;

  /// backend can still expose this, but it is now derived from today server-side
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

  DateTime get startDateLocal => _parseLocalDate(startAt);
  DateTime get endDateLocal => _parseLocalDate(endAt);

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

  // Optional/legacy (keep if your app still references it anywhere)
  final String? balanceFormatted;

  UserBalanceDto({
    required this.userId,
    required this.balanceCents,
    this.balanceFormatted,
  });

  factory UserBalanceDto.fromJson(Map<String, dynamic> j) {
    final idRaw = j['userId'] ?? j['id']; // accept both
    final userId = (idRaw ?? '').toString();

    int cents;
    final v = j['balanceCents'];
    if (v is num) {
      cents = v.toInt();
    } else {
      cents = int.tryParse((v ?? 0).toString()) ?? 0;
    }

    final bf = j['balanceFormatted'];
    final balanceFormatted = (bf == null) ? null : bf.toString();

    return UserBalanceDto(
      userId: userId,
      balanceCents: cents,
      balanceFormatted: balanceFormatted,
    );
  }

  Map<String, dynamic> toJson() => {
    // write both for cache compatibility across versions
    'userId': userId,
    'id': userId,
    'balanceCents': balanceCents,
    if (balanceFormatted != null) 'balanceFormatted': balanceFormatted,
  };
}

class LiveEventDto {
  final String id;
  final String title;
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
  final String? lastOnlineAt;

  UserDto({
    required this.id,
    required this.username,
    required this.displayName,
    required this.disabled,
    required this.roles,
    this.lastOnlineAt,
  });

  factory UserDto.fromJson(Map<String, dynamic> json) => UserDto(
    id: _reqString(json, 'id'),
    username: _reqString(json, 'username'),
    displayName: _reqString(json, 'displayName'),
    disabled: _optBool(json, 'disabled', fallback: false),
    roles: _optStringList(json, 'roles'),
    lastOnlineAt: _optString(json, 'lastOnlineAt'),
  );
}

class UserSessionDto {
  final String id;
  final String userId;
  final String appType;
  final String? deviceName;
  final String? deviceModel;
  final String? osName;
  final String? osVersion;
  final String? browserName;
  final String? browserVersion;
  final String? userAgent;
  final String createdAt;
  final String lastActiveAt;
  final String expiresAt;
  final String? revokedAt;
  final bool current;

  UserSessionDto({
    required this.id,
    required this.userId,
    required this.appType,
    required this.deviceName,
    required this.deviceModel,
    required this.osName,
    required this.osVersion,
    required this.browserName,
    required this.browserVersion,
    required this.userAgent,
    required this.createdAt,
    required this.lastActiveAt,
    required this.expiresAt,
    required this.revokedAt,
    required this.current,
  });

  factory UserSessionDto.fromJson(Map<String, dynamic> json) => UserSessionDto(
    id: _reqString(json, 'id'),
    userId: _reqString(json, 'userId'),
    appType: _optString(json, 'appType') ?? 'UNKNOWN',
    deviceName: _optString(json, 'deviceName'),
    deviceModel: _optString(json, 'deviceModel'),
    osName: _optString(json, 'osName'),
    osVersion: _optString(json, 'osVersion'),
    browserName: _optString(json, 'browserName'),
    browserVersion: _optString(json, 'browserVersion'),
    userAgent: _optString(json, 'userAgent'),
    createdAt: _reqString(json, 'createdAt'),
    lastActiveAt: _reqString(json, 'lastActiveAt'),
    expiresAt: _reqString(json, 'expiresAt'),
    revokedAt: _optString(json, 'revokedAt'),
    current: _optBool(json, 'current', fallback: false),
  );
}

class SessionStatsBucketDto {
  final String appType;
  final String browserName;
  final int count;

  SessionStatsBucketDto({
    required this.appType,
    required this.browserName,
    required this.count,
  });

  factory SessionStatsBucketDto.fromJson(Map<String, dynamic> json) =>
      SessionStatsBucketDto(
        appType: _optString(json, 'appType') ?? 'UNKNOWN',
        browserName: _optString(json, 'browserName') ?? 'UNKNOWN',
        count: _optInt(json, 'count'),
      );
}

class SessionStatsDto {
  final List<SessionStatsBucketDto> week;
  final List<SessionStatsBucketDto> month;
  final List<SessionStatsBucketDto> year;

  SessionStatsDto({
    required this.week,
    required this.month,
    required this.year,
  });

  factory SessionStatsDto.fromJson(Map<String, dynamic> json) => SessionStatsDto(
    week: _statsList(json, 'week'),
    month: _statsList(json, 'month'),
    year: _statsList(json, 'year'),
  );

  static List<SessionStatsBucketDto> _statsList(
      Map<String, dynamic> json,
      String key,
      ) {
    final v = json[key];
    if (v is! List) return const [];

    return v
        .whereType<Map>()
        .map((e) => SessionStatsBucketDto.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }
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
  final DateTime? solvedAt;

  final DateTime? dueAt;

  final bool recurringEnabled;
  final List<String> recurringWeekdays;
  final String? recurringDueTime;

  final List<UserPickerDto> assignees;
  final DateTime createdAt;

  TaskDto({
    required this.id,
    required this.creatorUserId,
    required this.title,
    required this.description,
    required this.solved,
    required this.solvedAt,
    required this.dueAt,
    required this.recurringEnabled,
    required this.recurringWeekdays,
    required this.recurringDueTime,
    required this.assignees,
    required this.createdAt,
  });

  factory TaskDto.fromJson(Map<String, dynamic> json) => TaskDto(
    id: _reqString(json, 'id'),
    creatorUserId: _reqString(json, 'creatorUserId'),
    title: _reqString(json, 'title'),
    description: _reqString(json, 'description'),
    solved: _optBool(json, 'solved'),
    solvedAt: _optDateTime(json, 'solvedAt'),
    dueAt: _optDateTime(json, 'dueAt'),
    recurringEnabled: _optBool(json, 'recurringEnabled'),
    recurringWeekdays: _optStringList(json, 'recurringWeekdays'),
    recurringDueTime: _optString(json, 'recurringDueTime'),
    assignees: _optList(json, 'assignees')
        .map((e) => UserPickerDto.fromJson(e))
        .toList(growable: false),
    createdAt: _optDateTimeOrEpoch(json, 'createdAt'),
  );
}

// ---------- TASKS: requests ----------

class CreateTaskRequest {
  final String title;
  final String description;
  final List<String> assigneeUserIds;

  /// OffsetDateTime on backend
  /// Normal task: required.
  /// Recurring task: must be omitted/null.
  final DateTime? dueAt;

  /// Recurring task fields
  final bool? recurringEnabled;
  final List<String>? recurringWeekdays;
  final String? recurringDueTime;

  CreateTaskRequest({
    required this.title,
    required this.description,
    required this.assigneeUserIds,
    this.dueAt,
    this.recurringEnabled,
    this.recurringWeekdays,
    this.recurringDueTime,
  });

  Map<String, dynamic> toJson() {
    final recurring = recurringEnabled == true;

    final m = <String, dynamic>{
      'title': title,
      'description': description,
      'assigneeUserIds': assigneeUserIds,
    };

    if (!recurring) {
      if (dueAt != null) {
        m['dueAt'] = dueAt!.toUtc().toIso8601String();
      }
      return m;
    }

    m['recurringEnabled'] = true;
    if (recurringWeekdays != null) m['recurringWeekdays'] = recurringWeekdays;
    if (recurringDueTime != null) m['recurringDueTime'] = recurringDueTime;
    return m;
  }
}

class UpdateTaskRequest {
  final String? title;
  final String? description;
  final List<String>? assigneeUserIds;

  final DateTime? dueAt;

  final bool? recurringEnabled;
  final List<String>? recurringWeekdays;
  final String? recurringDueTime;

  UpdateTaskRequest({
    this.title,
    this.description,
    this.assigneeUserIds,
    this.dueAt,
    this.recurringEnabled,
    this.recurringWeekdays,
    this.recurringDueTime,
  });

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};

    if (title != null) m['title'] = title;
    if (description != null) m['description'] = description;
    if (assigneeUserIds != null) m['assigneeUserIds'] = assigneeUserIds;

    if (dueAt != null) {
      m['dueAt'] = dueAt!.toUtc().toIso8601String();
    }

    if (recurringEnabled != null) m['recurringEnabled'] = recurringEnabled;
    if (recurringWeekdays != null) m['recurringWeekdays'] = recurringWeekdays;
    if (recurringDueTime != null) m['recurringDueTime'] = recurringDueTime;

    return m;
  }
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
  final String? decidedByUserId;
  final String? decidedAt;
  final String? acceptedFineId;
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
    required this.decidedByUserId,
    required this.decidedAt,
    required this.acceptedFineId,
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
    decidedByUserId: _optString(json, 'decidedByUserId'),
    decidedAt: _optString(json, 'decidedAt'),
    acceptedFineId: _optString(json, 'acceptedFineId'),
    targetUserIds: _optStringList(json, 'targetUserIds'),
    createdAt: _reqString(json, 'createdAt'),
  );
}

class UpdateFineSuggestionRequest {
  final String? fineDate;
  final List<String>? targetUserIds;
  final String? catalogItemId;
  final String? reason;
  final int? amountCents;

  UpdateFineSuggestionRequest({
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



class FineSuggestionPhotoDto {
  final String id;
  final String suggestionId;
  final String originalFilename;
  final String contentType;
  final int sizeBytes;
  final String createdAt;

  FineSuggestionPhotoDto({
    required this.id,
    required this.suggestionId,
    required this.originalFilename,
    required this.contentType,
    required this.sizeBytes,
    required this.createdAt,
  });

  factory FineSuggestionPhotoDto.fromJson(Map<String, dynamic> json) =>
      FineSuggestionPhotoDto(
        id: _reqString(json, 'id'),
        suggestionId: _reqString(json, 'suggestionId'),
        originalFilename: _reqString(json, 'originalFilename'),
        contentType: _reqString(json, 'contentType'),
        sizeBytes: _optInt(json, 'sizeBytes', fallback: 0),
        createdAt: _reqString(json, 'createdAt'),
      );
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

EventOwnerType _eventOwnerTypeFromJson(String s) =>
    (s == 'SENIOR') ? EventOwnerType.senior : EventOwnerType.housekeeping;

enum EventKind { main, secondary }

EventKind _eventKindFromJson(String s) =>
    (s == 'SECONDARY') ? EventKind.secondary : EventKind.main;

String _eventKindToJson(EventKind kind) =>
    (kind == EventKind.secondary) ? 'SECONDARY' : 'MAIN';

extension EventKindLabels on EventKind {
  String get labelDe {
    switch (this) {
      case EventKind.main:
        return 'Semesterprogrammveranstaltung';
      case EventKind.secondary:
        return 'Wochenplanveranstaltung';
    }
  }
}

class EventDto {
  final String id;
  final String creatorUserId;
  final String title;
  final String startsAt;
  final bool mandatory;
  final EventKind eventKind;
  final EventOwnerType ownerType;
  final String createdAt;

  EventDto({
    required this.id,
    required this.creatorUserId,
    required this.title,
    required this.startsAt,
    required this.mandatory,
    required this.eventKind,
    required this.ownerType,
    required this.createdAt,
  });

  factory EventDto.fromJson(Map<String, dynamic> json) => EventDto(
    id: _reqString(json, 'id'),
    creatorUserId: _reqString(json, 'creatorUserId'),
    title: _reqString(json, 'title'),
    startsAt: _reqString(json, 'startsAt'),
    mandatory: _optBool(json, 'mandatory', fallback: false),
    eventKind: _eventKindFromJson(_reqString({'eventKind': json['eventKind'] ?? 'MAIN'}, 'eventKind')),
    ownerType: _eventOwnerTypeFromJson(_reqString(json, 'ownerType')),
    createdAt: _reqString(json, 'createdAt'),
  );
}

class CreateEventRequest {
  final String title;
  final String startsAt;
  final bool mandatory;
  final EventKind eventKind;

  CreateEventRequest({
    required this.title,
    required this.startsAt,
    required this.mandatory,
    required this.eventKind,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'startsAt': startsAt,
    'mandatory': mandatory,
    'eventKind': _eventKindToJson(eventKind),
  };
}

class UpdateEventRequest {
  final String? title;
  final String? startsAt;
  final bool? mandatory;
  final EventKind? eventKind;

  UpdateEventRequest({
    this.title,
    this.startsAt,
    this.mandatory,
    this.eventKind,
  });

  Map<String, dynamic> toJson() => {
    if (title != null) 'title': title,
    if (startsAt != null) 'startsAt': startsAt,
    if (mandatory != null) 'mandatory': mandatory,
    if (eventKind != null) 'eventKind': _eventKindToJson(eventKind!),
  };
}

// ---------- Attendance ----------
enum AttendanceStatus { late, absent }

AttendanceStatus _attendanceStatusFromJson(String s) => (s == 'ABSENT') ? AttendanceStatus.absent : AttendanceStatus.late;

String _attendanceStatusToJson(AttendanceStatus s) => (s == AttendanceStatus.absent) ? 'ABSENT' : 'LATE';

class AttendanceDto {
  final String id;
  final String eventId;
  final String? periodId;
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
    periodId: _optString(json, 'periodId'),
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

// ---------- Attendance fines: requests/results ----------

class SetAttendanceFineConfigRequest {
  final String? lateCatalogItemId;
  final String? lateReason;
  final int? lateAmountCents;

  final String? absentCatalogItemId;
  final String? absentReason;
  final int? absentAmountCents;

  SetAttendanceFineConfigRequest({
    this.lateCatalogItemId,
    this.lateReason,
    this.lateAmountCents,
    this.absentCatalogItemId,
    this.absentReason,
    this.absentAmountCents,
  });

  Map<String, dynamic> toJson() => {
    if (lateCatalogItemId != null) 'lateCatalogItemId': lateCatalogItemId,
    if (lateReason != null) 'lateReason': lateReason,
    if (lateAmountCents != null) 'lateAmountCents': lateAmountCents,
    if (absentCatalogItemId != null) 'absentCatalogItemId': absentCatalogItemId,
    if (absentReason != null) 'absentReason': absentReason,
    if (absentAmountCents != null) 'absentAmountCents': absentAmountCents,
  };
}

class GenerateAttendanceFinesRequest {
  final bool dryRun;

  GenerateAttendanceFinesRequest({required this.dryRun});

  Map<String, dynamic> toJson() => {'dryRun': dryRun};
}

class GenerateAttendanceFinesResultDto {
  final int createdCount;
  final List<String> fineIds;

  GenerateAttendanceFinesResultDto({
    required this.createdCount,
    required this.fineIds,
  });

  factory GenerateAttendanceFinesResultDto.fromJson(Map<String, dynamic> json) =>
      GenerateAttendanceFinesResultDto(
        createdCount: _optInt(json, 'createdCount', fallback: 0),
        fineIds: (json['fineIds'] is List)
            ? (json['fineIds'] as List).map((e) => e.toString()).toList(growable: false)
            : const <String>[],
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

  /// date-only: YYYY-MM-DD
  final String startAt;

  /// date-only: YYYY-MM-DD
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

  /// date-only: YYYY-MM-DD
  final String? startAt;

  /// date-only: YYYY-MM-DD
  final String? endAt;

  /// active is derived on backend now -> do not send from frontend
  final bool? locked;

  UpdateConventPeriodRequest({
    this.semester,
    this.startAt,
    this.endAt,
    this.locked,
  });

  Map<String, dynamic> toJson() => {
    if (semester != null) 'semester': semester,
    if (startAt != null) 'startAt': startAt,
    if (endAt != null) 'endAt': endAt,
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