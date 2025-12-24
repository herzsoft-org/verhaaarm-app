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
