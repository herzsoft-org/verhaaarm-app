import 'package:jwt_decode/jwt_decode.dart';


enum AppRole { admin, senior, housekeeping, treasurer, member }

class Roles {
  static Set<AppRole> fromAccessToken(String? token) {
    if (token == null || token.isEmpty) return {};

    try {
      final payload = Jwt.parseJwt(token);

      // expecting something like: roles: ["ADMIN","SENIOR",...]
      final raw = payload['roles'];

      final List<dynamic> rolesList =
      (raw is List) ? raw : (raw is String ? [raw] : const []);

      return rolesList.map((e) => _mapRole(e.toString())).whereType<AppRole>().toSet();
    } catch (_) {
      return {};
    }
  }

  static AppRole? _mapRole(String r) {
    switch (r) {
      case 'ADMIN':
        return AppRole.admin;
      case 'SENIOR':
        return AppRole.senior;
      case 'HOUSEKEEPING':
        return AppRole.housekeeping;
      case 'TREASURER':
        return AppRole.treasurer;
      case 'MEMBER':
        return AppRole.member;
      default:
        return null;
    }
  }

  static bool canSeeAllFines(Set<AppRole> roles) {
    return roles.contains(AppRole.admin) ||
        roles.contains(AppRole.senior) ||
        roles.contains(AppRole.housekeeping) ||
        roles.contains(AppRole.treasurer);
  }

  static bool canCreateOfficialFine(Set<AppRole> roles) {
    return roles.contains(AppRole.admin) ||
        roles.contains(AppRole.senior) ||
        roles.contains(AppRole.housekeeping);
  }
}
