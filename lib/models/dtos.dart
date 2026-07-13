import 'member_status.dart';

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

int? _optionalIntField(Map<String, dynamic> j, String k) {
  final v = j[k];
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
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

bool? _optionalBoolField(Map<String, dynamic> j, String k) {
  final v = j[k];
  if (v == null) return null;
  if (v is bool) return v;
  final s = v.toString().toLowerCase();
  if (s == 'true') return true;
  if (s == 'false') return false;
  return null;
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

int? _optionalListLengthField(Map<String, dynamic> j, String k) {
  final v = j[k];
  return v is List ? v.length : null;
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

  final bool hasProtocolPdf;

  ConventPeriodDto({
    required this.id,
    required this.semester,
    required this.startAt,
    required this.endAt,
    required this.active,
    required this.locked,
    this.hasProtocolPdf = false,
  });

  DateTime get startDateLocal => _parseLocalDate(startAt);
  DateTime get endDateLocal => _parseLocalDate(endAt);

  factory ConventPeriodDto.fromJson(Map<String, dynamic> json) =>
      ConventPeriodDto(
        id: _reqString(json, 'id'),
        semester: _reqString(json, 'semester'),
        startAt: _reqString(json, 'startAt'),
        endAt: _reqString(json, 'endAt'),
        active: _optBool(json, 'active', fallback: false),
        locked: _optBool(json, 'locked', fallback: false),
        hasProtocolPdf: _optBool(json, 'hasProtocolPdf', fallback: false),
      );
}

class ConventPeriodProtocolDto {
  final String id;
  final String periodId;
  final String uploaderUserId;
  final String originalFilename;
  final String contentType;
  final int sizeBytes;
  final DateTime createdAt;
  final DateTime updatedAt;

  ConventPeriodProtocolDto({
    required this.id,
    required this.periodId,
    required this.uploaderUserId,
    required this.originalFilename,
    required this.contentType,
    required this.sizeBytes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ConventPeriodProtocolDto.fromJson(Map<String, dynamic> json) =>
      ConventPeriodProtocolDto(
        id: _reqString(json, 'id'),
        periodId: _reqString(json, 'periodId'),
        uploaderUserId: _reqString(json, 'uploaderUserId'),
        originalFilename: _reqString(json, 'originalFilename'),
        contentType: _optString(json, 'contentType') ?? 'application/pdf',
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
        createdAt: _reqDateTime(json, 'createdAt'),
        updatedAt: _reqDateTime(json, 'updatedAt'),
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
  final LiveEventReactionSummary reactions;
  final LiveEventReactionUsers? reactionUsers;

  LiveEventDto({
    required this.id,
    required this.title,
    required this.place,
    required this.description,
    required this.createdByUserId,
    required this.createdAt,
    required this.expiresAt,
    this.reactions = const LiveEventReactionSummary(),
    this.reactionUsers,
  });

  factory LiveEventDto.fromJson(Map<String, dynamic> json) => LiveEventDto(
    id: _reqString(json, 'id'),
    title: _reqString(json, 'title'),
    place: _optString(json, 'place'),
    description: _optString(json, 'description'),
    createdByUserId: _reqString(json, 'createdByUserId'),
    createdAt: _reqString(json, 'createdAt'),
    expiresAt: _reqString(json, 'expiresAt'),
    reactions: json['reactions'] is Map
        ? LiveEventReactionSummary.fromJson(
            (json['reactions'] as Map).cast<String, dynamic>(),
          )
        : const LiveEventReactionSummary(),
    reactionUsers: json['reactionUsers'] is Map
        ? LiveEventReactionUsers.fromJson(
            (json['reactionUsers'] as Map).cast<String, dynamic>(),
          )
        : null,
  );

  LiveEventDto copyWith({
    String? id,
    String? title,
    String? place,
    String? description,
    String? createdByUserId,
    String? createdAt,
    String? expiresAt,
    LiveEventReactionSummary? reactions,
    LiveEventReactionUsers? reactionUsers,
  }) {
    return LiveEventDto(
      id: id ?? this.id,
      title: title ?? this.title,
      place: place ?? this.place,
      description: description ?? this.description,
      createdByUserId: createdByUserId ?? this.createdByUserId,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      reactions: reactions ?? this.reactions,
      reactionUsers: reactionUsers ?? this.reactionUsers,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'place': place,
    'description': description,
    'createdByUserId': createdByUserId,
    'createdAt': createdAt,
    'expiresAt': expiresAt,
    'reactions': reactions.toJson(),
    if (reactionUsers != null) 'reactionUsers': reactionUsers!.toJson(),
  };
}

enum LiveEventReactionType {
  prost('PROST'),
  ichKomme('ICH_KOMME');

  final String apiValue;
  const LiveEventReactionType(this.apiValue);
}

class LiveEventReactionSummary {
  final int prostCount;
  final int ichKommeCount;
  final bool reactedProst;
  final bool reactedIchKomme;

  const LiveEventReactionSummary({
    this.prostCount = 0,
    this.ichKommeCount = 0,
    this.reactedProst = false,
    this.reactedIchKomme = false,
  });

  factory LiveEventReactionSummary.fromJson(Map<String, dynamic> json) {
    return LiveEventReactionSummary(
      prostCount: _optInt(json, 'prostCount'),
      ichKommeCount: _optInt(json, 'ichKommeCount'),
      reactedProst: _optBool(json, 'reactedProst'),
      reactedIchKomme: _optBool(json, 'reactedIchKomme'),
    );
  }

  int countFor(LiveEventReactionType type) {
    return switch (type) {
      LiveEventReactionType.prost => prostCount,
      LiveEventReactionType.ichKomme => ichKommeCount,
    };
  }

  bool reactedFor(LiveEventReactionType type) {
    return switch (type) {
      LiveEventReactionType.prost => reactedProst,
      LiveEventReactionType.ichKomme => reactedIchKomme,
    };
  }

  Map<String, dynamic> toJson() => {
    'prostCount': prostCount,
    'ichKommeCount': ichKommeCount,
    'reactedProst': reactedProst,
    'reactedIchKomme': reactedIchKomme,
  };
}

class LiveEventReactionUserDto {
  final String id;
  final String displayName;

  const LiveEventReactionUserDto({required this.id, required this.displayName});

  factory LiveEventReactionUserDto.fromJson(Map<String, dynamic> json) {
    return LiveEventReactionUserDto(
      id: _reqString(json, 'id'),
      displayName: _reqString(json, 'displayName'),
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'displayName': displayName};
}

class LiveEventReactionUsers {
  final List<LiveEventReactionUserDto> prost;
  final List<LiveEventReactionUserDto> ichKomme;

  const LiveEventReactionUsers({
    this.prost = const [],
    this.ichKomme = const [],
  });

  factory LiveEventReactionUsers.fromJson(Map<String, dynamic> json) {
    List<LiveEventReactionUserDto> users(String key) => _optList(
      json,
      key,
    ).map(LiveEventReactionUserDto.fromJson).toList(growable: false);

    return LiveEventReactionUsers(
      prost: users('prost'),
      ichKomme: users('ichKomme'),
    );
  }

  List<LiveEventReactionUserDto> usersFor(LiveEventReactionType type) {
    return switch (type) {
      LiveEventReactionType.prost => prost,
      LiveEventReactionType.ichKomme => ichKomme,
    };
  }

  Map<String, dynamic> toJson() => {
    'prost': prost.map((u) => u.toJson()).toList(growable: false),
    'ichKomme': ichKomme.map((u) => u.toJson()).toList(growable: false),
  };
}

class LiveEventReactionToggleResult {
  final LiveEventDto? event;
  final LiveEventReactionSummary? summary;

  const LiveEventReactionToggleResult({this.event, this.summary});
}

// ---------- Users (Picker) ----------
class UserPickerDto {
  final String id;
  final String username;
  final String displayName;
  final String memberStatus;
  final bool actividad;
  final bool disabled;

  bool get aktivitas => actividad;

  UserPickerDto({
    required this.id,
    required this.username,
    required this.displayName,
    required this.memberStatus,
    required this.actividad,
    this.disabled = false,
  });

  factory UserPickerDto.fromJson(Map<String, dynamic> json) => UserPickerDto(
    id: _reqString(json, 'id'),
    username: _reqString(json, 'username'),
    displayName: _reqString(json, 'displayName'),
    memberStatus: _memberStatusFromJson(json),
    actividad: _aktivitasFromJson(json),
    disabled: _optBool(json, 'disabled'),
  );
}

class UserDto {
  final String id;
  final String username;
  final String displayName;
  final bool disabled;
  final List<String> roles;
  final String memberStatus;
  final bool actividad;
  final String? lastOnlineAt;
  final DateTime? updatedAt;

  bool get aktivitas => actividad;

  UserDto({
    required this.id,
    required this.username,
    required this.displayName,
    required this.disabled,
    required this.roles,
    required this.memberStatus,
    required this.actividad,
    this.lastOnlineAt,
    this.updatedAt,
  });

  factory UserDto.fromJson(Map<String, dynamic> json) => UserDto(
    id: _reqString(json, 'id'),
    username: _reqString(json, 'username'),
    displayName: _reqString(json, 'displayName'),
    disabled: _optBool(json, 'disabled', fallback: false),
    roles: _optStringList(json, 'roles'),
    memberStatus: _memberStatusFromJson(json),
    actividad: _aktivitasFromJson(json),
    lastOnlineAt: _optString(json, 'lastOnlineAt'),
    updatedAt: _optDateTime(json, 'updatedAt'),
  );
}

class UserSessionDto {
  final String id;
  final String? userId;
  final String? username;
  final String? displayName;
  final String appType;
  final String? deviceName;
  final String? deviceModel;
  final String? osName;
  final String? osVersion;
  final String? browserName;
  final String? browserVersion;
  final String? userAgent;
  final String? ipAddress;
  final String? countryCode;
  final String? createdAt;
  final String? lastActiveAt;
  final String? expiresAt;
  final String? revokedAt;
  final bool current;

  UserSessionDto({
    required this.id,
    required this.userId,
    required this.username,
    required this.displayName,
    required this.appType,
    required this.deviceName,
    required this.deviceModel,
    required this.osName,
    required this.osVersion,
    required this.browserName,
    required this.browserVersion,
    required this.userAgent,
    required this.ipAddress,
    required this.countryCode,
    required this.createdAt,
    required this.lastActiveAt,
    required this.expiresAt,
    required this.revokedAt,
    required this.current,
  });

  factory UserSessionDto.fromJson(Map<String, dynamic> json) => UserSessionDto(
    id: _reqString(json, 'id'),
    userId: _optString(json, 'userId'),
    username: _optString(json, 'username'),
    displayName: _optString(json, 'displayName'),
    appType: _optString(json, 'appType') ?? 'UNKNOWN',
    deviceName: _optString(json, 'deviceName'),
    deviceModel: _optString(json, 'deviceModel'),
    osName: _optString(json, 'osName'),
    osVersion: _optString(json, 'osVersion'),
    browserName: _optString(json, 'browserName'),
    browserVersion: _optString(json, 'browserVersion'),
    userAgent: _optString(json, 'userAgent'),
    ipAddress: _optString(json, 'ipAddress'),
    countryCode: _optString(json, 'countryCode'),
    createdAt: _optString(json, 'createdAt'),
    lastActiveAt: _optString(json, 'lastActiveAt'),
    expiresAt: _optString(json, 'expiresAt'),
    revokedAt: _optString(json, 'revokedAt'),
    current: _optBool(json, 'current', fallback: false),
  );
}

class SessionStatsBucketDto {
  final String appType;
  final String detail;
  final int count;

  SessionStatsBucketDto({
    required this.appType,
    required this.detail,
    required this.count,
  });

  factory SessionStatsBucketDto.fromJson(Map<String, dynamic> json) {
    return SessionStatsBucketDto(
      appType: (json['appType'] as String?) ?? 'UNKNOWN',
      detail:
          (json['detail'] as String?) ??
          (json['browserName'] as String?) ??
          'Unbekannt',
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }
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

  factory SessionStatsDto.fromJson(Map<String, dynamic> json) =>
      SessionStatsDto(
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
  final String memberStatus;

  CreateUserRequest({
    required this.username,
    required this.displayName,
    required this.password,
    required this.roles,
    this.memberStatus = 'BURSCH',
  });

  Map<String, dynamic> toJson() => {
    'username': username,
    'displayName': displayName,
    'password': password,
    'roles': roles,
    'memberStatus': memberStatus,
  };
}

class UpdateUserRequest {
  final String? displayName;
  final bool? disabled;
  final List<String>? roles;
  final String? memberStatus;

  UpdateUserRequest({
    this.displayName,
    this.disabled,
    this.roles,
    this.memberStatus,
  });

  Map<String, dynamic> toJson() => {
    if (displayName != null) 'displayName': displayName,
    if (disabled != null) 'disabled': disabled,
    if (roles != null) 'roles': roles,
    if (memberStatus != null) 'memberStatus': memberStatus,
  };
}

class PaukstundenParticipantDto {
  final String id;
  final String username;
  final String displayName;
  final String memberStatus;

  PaukstundenParticipantDto({
    required this.id,
    required this.username,
    required this.displayName,
    required this.memberStatus,
  });

  factory PaukstundenParticipantDto.fromJson(Map<String, dynamic> json) {
    return PaukstundenParticipantDto(
      id: _optString(json, 'id') ?? _optString(json, 'userId') ?? '',
      username: _reqString(json, 'username'),
      displayName: _reqString(json, 'displayName'),
      memberStatus: _memberStatusFromJson(json),
    );
  }
}

class PaukstundenEntryDto {
  final String id;
  final String date;
  final int hours;
  final List<PaukstundenParticipantDto> participants;
  final String createdByUserId;
  final String createdByDisplayName;
  final String createdAt;
  final String updatedAt;

  PaukstundenEntryDto({
    required this.id,
    required this.date,
    required this.hours,
    required this.participants,
    required this.createdByUserId,
    required this.createdByDisplayName,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PaukstundenEntryDto.fromJson(Map<String, dynamic> json) {
    return PaukstundenEntryDto(
      id: _reqString(json, 'id'),
      date: _reqString(json, 'date'),
      hours: _optInt(json, 'hours'),
      participants: _optList(
        json,
        'participants',
      ).map(PaukstundenParticipantDto.fromJson).toList(growable: false),
      createdByUserId: _reqString(json, 'createdByUserId'),
      createdByDisplayName: _reqString(json, 'createdByDisplayName'),
      createdAt: _reqString(json, 'createdAt'),
      updatedAt: _reqString(json, 'updatedAt'),
    );
  }
}

class CreatePaukstundeRequest {
  final String date;
  final int hours;
  final List<String> participantUserIds;

  CreatePaukstundeRequest({
    required this.date,
    required this.hours,
    required this.participantUserIds,
  });

  Map<String, dynamic> toJson() => {
    'date': date,
    'hours': hours,
    'participantUserIds': participantUserIds,
  };
}

class UpdatePaukstundeRequest {
  final String? date;
  final int? hours;
  final List<String>? participantUserIds;

  UpdatePaukstundeRequest({this.date, this.hours, this.participantUserIds});

  Map<String, dynamic> toJson() => {
    if (date != null) 'date': date,
    if (hours != null) 'hours': hours,
    if (participantUserIds != null) 'participantUserIds': participantUserIds,
  };
}

class PaukstundenUserSummaryDto {
  final String userId;
  final String username;
  final String displayName;
  final String memberStatus;
  final int totalHours;
  final int entryCount;
  final List<PaukstundenEntryDto> entries;

  PaukstundenUserSummaryDto({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.memberStatus,
    required this.totalHours,
    required this.entryCount,
    required this.entries,
  });

  factory PaukstundenUserSummaryDto.fromJson(Map<String, dynamic> json) {
    final entries = _extractPaukstundenEntries(json);
    final id = _optString(json, 'userId') ?? _optString(json, 'id') ?? '';
    return PaukstundenUserSummaryDto(
      userId: id,
      username: _reqString(json, 'username'),
      displayName: _reqString(json, 'displayName'),
      memberStatus: _memberStatusFromJson(json),
      totalHours: _optInt(
        json,
        'totalHours',
        fallback: entries.fold<int>(0, (sum, e) => sum + e.hours),
      ),
      entryCount: _optInt(json, 'entryCount', fallback: entries.length),
      entries: entries,
    );
  }
}

class PaukstundenListDto {
  final int totalHours;
  final int entryCount;
  final List<PaukstundenEntryDto> entries;

  PaukstundenListDto({
    required this.totalHours,
    required this.entryCount,
    required this.entries,
  });

  factory PaukstundenListDto.fromJson(Object data) {
    if (data is List) {
      final entries = data
          .whereType<Map>()
          .map((e) => PaukstundenEntryDto.fromJson(e.cast<String, dynamic>()))
          .toList(growable: false);
      return PaukstundenListDto.fromEntries(entries);
    }

    if (data is Map) {
      final json = data.cast<String, dynamic>();
      final entries = _extractPaukstundenEntries(json);
      return PaukstundenListDto(
        totalHours: _optInt(
          json,
          'totalHours',
          fallback: entries.fold<int>(0, (sum, e) => sum + e.hours),
        ),
        entryCount: _optInt(json, 'entryCount', fallback: entries.length),
        entries: entries,
      );
    }

    return PaukstundenListDto.fromEntries(const []);
  }

  factory PaukstundenListDto.fromEntries(List<PaukstundenEntryDto> entries) {
    return PaukstundenListDto(
      totalHours: entries.fold<int>(0, (sum, e) => sum + e.hours),
      entryCount: entries.length,
      entries: entries,
    );
  }
}

class PaukstundenSummaryDto {
  final String? periodId;
  final String? periodLabel;
  final List<PaukstundenUserSummaryDto> users;

  PaukstundenSummaryDto({required this.users, this.periodId, this.periodLabel});

  factory PaukstundenSummaryDto.fromJson(Object data) {
    if (data is List) {
      return PaukstundenSummaryDto(
        users: data
            .whereType<Map>()
            .map(
              (e) =>
                  PaukstundenUserSummaryDto.fromJson(e.cast<String, dynamic>()),
            )
            .toList(growable: false),
      );
    }

    if (data is Map) {
      final json = data.cast<String, dynamic>();
      final rawUsers =
          json['users'] ?? json['summaries'] ?? json['items'] ?? json['data'];
      final users = rawUsers is List
          ? rawUsers
                .whereType<Map>()
                .map(
                  (e) => PaukstundenUserSummaryDto.fromJson(
                    e.cast<String, dynamic>(),
                  ),
                )
                .toList(growable: false)
          : const <PaukstundenUserSummaryDto>[];

      return PaukstundenSummaryDto(
        periodId:
            _optString(json, 'periodId') ??
            _optString(json, 'conventsperiodeId'),
        periodLabel:
            _optString(json, 'periodLabel') ??
            _optString(json, 'conventsperiodeLabel') ??
            _optString(json, 'semester'),
        users: users,
      );
    }

    return PaukstundenSummaryDto(users: const []);
  }
}

List<PaukstundenEntryDto> _extractPaukstundenEntries(
  Map<String, dynamic> json,
) {
  final raw =
      json['entries'] ?? json['paukstunden'] ?? json['items'] ?? json['data'];
  if (raw is! List) return const <PaukstundenEntryDto>[];
  return raw
      .whereType<Map>()
      .map((e) => PaukstundenEntryDto.fromJson(e.cast<String, dynamic>()))
      .toList(growable: false);
}

String _memberStatusFromJson(Map<String, dynamic> json) {
  final raw = _optString(json, 'memberStatus');

  if (raw != null && raw.trim().isNotEmpty) {
    return raw.trim().toUpperCase();
  }

  final actividad = _optBool(json, 'aktivitas', fallback: true);

  if (!actividad) return 'PHILISTER';

  return 'BURSCH';
}

bool _aktivitasFromJson(Map<String, dynamic> json) {
  final explicit = json['aktivitas'];

  if (explicit is bool) return explicit;

  final rawStatus = _optString(json, 'memberStatus');
  return MemberStatuses.isAktivitas(rawStatus);
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
    assignees: _optList(
      json,
      'assignees',
    ).map((e) => UserPickerDto.fromJson(e)).toList(growable: false),
    createdAt: _optDateTimeOrEpoch(json, 'createdAt'),
  );
}

// ---------- TASKS: requests ----------

class CreateTaskRequest {
  final String title;
  final String description;
  final List<String> assigneeUserIds;
  final bool notifyOnlyMe;

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
    this.notifyOnlyMe = false,
  });

  Map<String, dynamic> toJson() {
    final recurring = recurringEnabled == true;

    final m = <String, dynamic>{
      'title': title,
      'description': description,
      'assigneeUserIds': assigneeUserIds,
      if (notifyOnlyMe) 'notifyOnlyMe': true,
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

  factory FineCatalogItemDto.fromJson(Map<String, dynamic> json) =>
      FineCatalogItemDto(
        id: _reqString(json, 'id'),
        title: _reqString(json, 'title'),
        defaultAmountCents: json['defaultAmountCents'] == null
            ? null
            : _optInt(json, 'defaultAmountCents'),
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

  UpdateFineCatalogItemRequest({
    this.title,
    this.defaultAmountCents,
    this.active,
  });

  Map<String, dynamic> toJson() => {
    if (title != null) 'title': title,
    if (defaultAmountCents != null) 'defaultAmountCents': defaultAmountCents,
    if (active != null) 'active': active,
  };
}

// ---------- Fines ----------
enum FineType { catalog, custom }

FineType _fineTypeFromJson(String s) =>
    (s == 'CATALOG') ? FineType.catalog : FineType.custom;

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
  final int? photoCount;
  final bool? hasPhotos;

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
    required this.photoCount,
    required this.hasPhotos,
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
    amountCents: json['amountCents'] == null
        ? null
        : _optInt(json, 'amountCents'),
    type: _fineTypeFromJson(_reqString(json, 'type')),
    targetUserIds: _optStringList(json, 'targetUserIds'),
    photoCount:
        _optionalIntField(json, 'photoCount') ??
        _optionalIntField(json, 'photosCount') ??
        _optionalListLengthField(json, 'photos'),
    hasPhotos: _optionalBoolField(json, 'hasPhotos'),
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
  final bool notifyOnlyMe;

  CreateFineRequest({
    required this.fineDate,
    required this.targetUserIds,
    this.catalogItemId,
    this.reason,
    this.amountCents,
    this.notifyOnlyMe = false,
  });

  Map<String, dynamic> toJson() => {
    'fineDate': fineDate,
    'targetUserIds': targetUserIds,
    if (catalogItemId != null) 'catalogItemId': catalogItemId,
    if (reason != null) 'reason': reason,
    if (amountCents != null) 'amountCents': amountCents,
    if (notifyOnlyMe) 'notifyOnlyMe': true,
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

  Map<String, dynamic> toJson() => {'text': text, 'author': author};
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

  factory FineSuggestionDto.fromJson(Map<String, dynamic> json) =>
      FineSuggestionDto(
        id: _reqString(json, 'id'),
        fineDate: _reqString(json, 'fineDate'),
        creatorUserId: _reqString(json, 'creatorUserId'),
        catalogItemId: _optString(json, 'catalogItemId'),
        reason: _optString(json, 'reason'),
        amountCents: json['amountCents'] == null
            ? null
            : _optInt(json, 'amountCents'),
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

  factory FineDtoAcceptResult.fromJson(Map<String, dynamic> json) =>
      FineDtoAcceptResult(
        fineId: _optString(json, 'fineId'),
        fine: (json['fine'] is Map<String, dynamic>)
            ? FineDto.fromJson(json['fine'] as Map<String, dynamic>)
            : null,
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
    eventKind: _eventKindFromJson(
      _reqString({'eventKind': json['eventKind'] ?? 'MAIN'}, 'eventKind'),
    ),
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

AttendanceStatus _attendanceStatusFromJson(String s) =>
    (s == 'ABSENT') ? AttendanceStatus.absent : AttendanceStatus.late;

String _attendanceStatusToJson(AttendanceStatus s) =>
    (s == AttendanceStatus.absent) ? 'ABSENT' : 'LATE';

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
    lateMinutes: json['lateMinutes'] == null
        ? null
        : _optInt(json, 'lateMinutes'),
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

  factory AttendanceFineConfigDto.fromJson(Map<String, dynamic> json) =>
      AttendanceFineConfigDto(
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

  factory GenerateAttendanceFinesResultDto.fromJson(
    Map<String, dynamic> json,
  ) => GenerateAttendanceFinesResultDto(
    createdCount: _optInt(json, 'createdCount', fallback: 0),
    fineIds: (json['fineIds'] is List)
        ? (json['fineIds'] as List)
              .map((e) => e.toString())
              .toList(growable: false)
        : const <String>[],
  );
}

// ---------- Live Events ----------
class CreateLiveEventRequest {
  final String title;
  final String place;
  final String description;
  final bool notifyOnlyMe;

  CreateLiveEventRequest({
    required this.title,
    required this.place,
    required this.description,
    this.notifyOnlyMe = false,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'place': place,
    'description': description,
    if (notifyOnlyMe) 'notifyOnlyMe': true,
  };
}

class UpdateLiveEventRequest {
  final String? title;
  final String? place;
  final String? description;

  UpdateLiveEventRequest({this.title, this.place, this.description});

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
    final rawData = (json['data'] is Map)
        ? (json['data'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
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

  NotificationDto copyWith({DateTime? readAt}) {
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

  factory UnreadCountDto.fromJson(Map<String, dynamic> json) =>
      UnreadCountDto(unread: _optInt(json, 'unread', fallback: 0));
}

class UserSettingValueDto {
  final String value;
  final DateTime? updatedAt;

  const UserSettingValueDto({required this.value, required this.updatedAt});

  factory UserSettingValueDto.fromJson(Map<String, dynamic> json) {
    return UserSettingValueDto(
      value: (json['value'] ?? '').toString(),
      updatedAt: _optDateTime(json, 'updatedAt'),
    );
  }
}

class UserSettingsResponseDto {
  final DateTime? serverTime;
  final Map<String, UserSettingValueDto> settings;

  const UserSettingsResponseDto({
    required this.serverTime,
    required this.settings,
  });

  factory UserSettingsResponseDto.fromJson(Map<String, dynamic> json) {
    final rawSettings = json['settings'];
    final parsed = <String, UserSettingValueDto>{};

    if (rawSettings is Map) {
      for (final entry in rawSettings.entries) {
        final key = entry.key.toString();
        final value = entry.value;

        if (value is Map) {
          parsed[key] = UserSettingValueDto.fromJson(
            value.cast<String, dynamic>(),
          );
        }
      }
    }

    return UserSettingsResponseDto(
      serverTime: _optDateTime(json, 'serverTime'),
      settings: Map.unmodifiable(parsed),
    );
  }
}

class UserSettingPatchDto {
  final String key;
  final String value;
  final DateTime changedAt;

  const UserSettingPatchDto({
    required this.key,
    required this.value,
    required this.changedAt,
  });

  Map<String, dynamic> toJson() => {
    'key': key,
    'value': value,
    'changedAt': changedAt.toUtc().toIso8601String(),
  };
}

// ---------------- SLUSHY RECIPES ----------------

class SlushyIngredientDto {
  final String? id;
  final String name;
  final String? amount;

  const SlushyIngredientDto({this.id, required this.name, this.amount});

  factory SlushyIngredientDto.fromJson(Map<String, dynamic> json) =>
      SlushyIngredientDto(
        id: _optString(json, 'id'),
        name: _reqString(json, 'name'),
        amount: _optString(json, 'amount'),
      );

  Map<String, dynamic> toJson() => {'name': name, if (amount != null) 'amount': amount};
}

class SlushyRecipeRatingDto {
  final String userId;
  final String displayName;
  final int stars;
  final String? comment;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SlushyRecipeRatingDto({
    required this.userId,
    required this.displayName,
    required this.stars,
    this.comment,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SlushyRecipeRatingDto.fromJson(Map<String, dynamic> json) =>
      SlushyRecipeRatingDto(
        userId: _reqString(json, 'userId'),
        displayName: _reqString(json, 'displayName'),
        stars: _optInt(json, 'stars'),
        comment: _optString(json, 'comment'),
        createdAt: _optDateTimeOrEpoch(json, 'createdAt'),
        updatedAt: _optDateTimeOrEpoch(json, 'updatedAt'),
      );
}

class SlushyRecipeRatingSummaryDto {
  final double average;
  final int count;
  final int? myStars;
  final String? myComment;

  const SlushyRecipeRatingSummaryDto({
    this.average = 0,
    this.count = 0,
    this.myStars,
    this.myComment,
  });

  factory SlushyRecipeRatingSummaryDto.fromJson(Map<String, dynamic> json) {
    final avg = json['average'];
    return SlushyRecipeRatingSummaryDto(
      average: avg is num ? avg.toDouble() : 0,
      count: _optInt(json, 'count'),
      myStars: _optionalIntField(json, 'myStars'),
      myComment: _optString(json, 'myComment'),
    );
  }
}

class SlushyRecipeDto {
  final String id;
  final String title;
  final String? description;
  final List<SlushyIngredientDto> ingredients;
  final String? createdByUserId;
  final String? createdByDisplayName;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SlushyRecipeRatingSummaryDto ratingSummary;
  final List<SlushyRecipeRatingDto> ratings;

  const SlushyRecipeDto({
    required this.id,
    required this.title,
    this.description,
    this.ingredients = const [],
    this.createdByUserId,
    this.createdByDisplayName,
    required this.createdAt,
    required this.updatedAt,
    this.ratingSummary = const SlushyRecipeRatingSummaryDto(),
    this.ratings = const [],
  });

  factory SlushyRecipeDto.fromJson(Map<String, dynamic> json) => SlushyRecipeDto(
    id: _reqString(json, 'id'),
    title: _reqString(json, 'title'),
    description: _optString(json, 'description'),
    ingredients: _optList(
      json,
      'ingredients',
    ).map(SlushyIngredientDto.fromJson).toList(growable: false),
    createdByUserId: _optString(json, 'createdByUserId'),
    createdByDisplayName: _optString(json, 'createdByDisplayName'),
    createdAt: _optDateTimeOrEpoch(json, 'createdAt'),
    updatedAt: _optDateTimeOrEpoch(json, 'updatedAt'),
    ratingSummary: json['ratingSummary'] is Map
        ? SlushyRecipeRatingSummaryDto.fromJson(
            (json['ratingSummary'] as Map).cast<String, dynamic>(),
          )
        : const SlushyRecipeRatingSummaryDto(),
    ratings: _optList(
      json,
      'ratings',
    ).map(SlushyRecipeRatingDto.fromJson).toList(growable: false),
  );
}

class CreateSlushyRecipeRequest {
  final String title;
  final String? description;
  final List<SlushyIngredientDto> ingredients;

  CreateSlushyRecipeRequest({
    required this.title,
    this.description,
    this.ingredients = const [],
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    if (description != null) 'description': description,
    'ingredients': ingredients.map((i) => i.toJson()).toList(growable: false),
  };
}

class UpdateSlushyRecipeRequest {
  final String? title;
  final String? description;
  final List<SlushyIngredientDto>? ingredients;

  UpdateSlushyRecipeRequest({this.title, this.description, this.ingredients});

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    if (title != null) m['title'] = title;
    if (description != null) m['description'] = description;
    if (ingredients != null) {
      m['ingredients'] = ingredients!.map((i) => i.toJson()).toList(growable: false);
    }
    return m;
  }
}

class RateSlushyRecipeRequest {
  final int stars;
  final String? comment;

  RateSlushyRecipeRequest({required this.stars, this.comment});

  Map<String, dynamic> toJson() => {
    'stars': stars,
    if (comment != null) 'comment': comment,
  };
}

// ---------- AEMTER ----------

class AmtHolderDto {
  final String userId;
  final String displayName;

  AmtHolderDto({required this.userId, required this.displayName});

  factory AmtHolderDto.fromJson(Map<String, dynamic> json) => AmtHolderDto(
    userId: _reqString(json, 'userId'),
    displayName: _reqString(json, 'displayName'),
  );
}

class AmtSubLineDto {
  final String displayTitle;
  final List<AmtHolderDto> holders;

  AmtSubLineDto({required this.displayTitle, required this.holders});

  factory AmtSubLineDto.fromJson(Map<String, dynamic> json) => AmtSubLineDto(
    displayTitle: _reqString(json, 'displayTitle'),
    holders: _optList(
      json,
      'holders',
    ).map(AmtHolderDto.fromJson).toList(growable: false),
  );
}

class AmtGroupLineDto {
  final String amtType;
  final String baseLabel;
  final List<AmtSubLineDto> lines;

  AmtGroupLineDto({
    required this.amtType,
    required this.baseLabel,
    required this.lines,
  });

  factory AmtGroupLineDto.fromJson(Map<String, dynamic> json) =>
      AmtGroupLineDto(
        amtType: _reqString(json, 'amtType'),
        baseLabel: _reqString(json, 'baseLabel'),
        lines: _optList(
          json,
          'lines',
        ).map(AmtSubLineDto.fromJson).toList(growable: false),
      );
}

class AmtEntryDto {
  final String amtType;
  final String label;
  final bool autoFromRole;
  final bool mergedIntoEhrengericht;
  final List<AmtHolderDto> holders;

  AmtEntryDto({
    required this.amtType,
    required this.label,
    required this.autoFromRole,
    required this.mergedIntoEhrengericht,
    required this.holders,
  });

  factory AmtEntryDto.fromJson(Map<String, dynamic> json) => AmtEntryDto(
    amtType: _reqString(json, 'amtType'),
    label: _reqString(json, 'label'),
    autoFromRole: _optBool(json, 'autoFromRole'),
    mergedIntoEhrengericht: _optBool(json, 'mergedIntoEhrengericht'),
    holders: _optList(
      json,
      'holders',
    ).map(AmtHolderDto.fromJson).toList(growable: false),
  );
}

class AemterOverviewDto {
  final List<AmtGroupLineDto> ehrengericht;
  final List<AmtEntryDto> other;

  AemterOverviewDto({required this.ehrengericht, required this.other});

  factory AemterOverviewDto.fromJson(Map<String, dynamic> json) =>
      AemterOverviewDto(
        ehrengericht: _optList(
          json,
          'ehrengericht',
        ).map(AmtGroupLineDto.fromJson).toList(growable: false),
        other: _optList(
          json,
          'other',
        ).map(AmtEntryDto.fromJson).toList(growable: false),
      );
}

// ---------- FERIENVERTRETER ----------

class FerienvertreterDto {
  final String id;
  final UserPickerDto person;

  /// date-only: YYYY-MM-DD
  final String fromDate;

  /// date-only: YYYY-MM-DD
  final String untilDate;

  FerienvertreterDto({
    required this.id,
    required this.person,
    required this.fromDate,
    required this.untilDate,
  });

  DateTime get fromDateLocal => _parseLocalDate(fromDate);
  DateTime get untilDateLocal => _parseLocalDate(untilDate);

  factory FerienvertreterDto.fromJson(Map<String, dynamic> json) =>
      FerienvertreterDto(
        id: _reqString(json, 'id'),
        person: UserPickerDto.fromJson(
          (json['person'] as Map).cast<String, dynamic>(),
        ),
        fromDate: _reqString(json, 'fromDate'),
        untilDate: _reqString(json, 'untilDate'),
      );
}

class CreateFerienvertreterRequest {
  final String userId;

  /// date-only: YYYY-MM-DD
  final String fromDate;

  /// date-only: YYYY-MM-DD
  final String untilDate;

  CreateFerienvertreterRequest({
    required this.userId,
    required this.fromDate,
    required this.untilDate,
  });

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'fromDate': fromDate,
    'untilDate': untilDate,
  };
}

class UpdateFerienvertreterRequest {
  final String? userId;

  /// date-only: YYYY-MM-DD
  final String? fromDate;

  /// date-only: YYYY-MM-DD
  final String? untilDate;

  UpdateFerienvertreterRequest({this.userId, this.fromDate, this.untilDate});

  Map<String, dynamic> toJson() => {
    if (userId != null) 'userId': userId,
    if (fromDate != null) 'fromDate': fromDate,
    if (untilDate != null) 'untilDate': untilDate,
  };
}
