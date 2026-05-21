import 'package:jwt_decode/jwt_decode.dart';

enum AppRole { admin, senior, housekeeping, treasurer, member }

class Roles {
  static Set<AppRole> fromAccessToken(String? token) {
    if (token == null || token.isEmpty) return {};

    try {
      final payload = Jwt.parseJwt(token);

      // expecting something like: roles: ["ADMIN","SENIOR",...]
      final raw = payload['roles'];
      final List<dynamic> rolesList = (raw is List) ? raw : (raw is String ? [raw] : const []);

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

  static bool canViewFineDetails(Set<AppRole> roles) {
    return canSeeAllFines(roles);
  }

  static bool canAcceptFineSuggestions(Set<AppRole> roles) {
    return roles.contains(AppRole.admin) || roles.contains(AppRole.senior) || roles.contains(AppRole.housekeeping);
  }

  static bool canCreateOfficialFine(Set<AppRole> roles) {
    return roles.contains(AppRole.admin) || roles.contains(AppRole.senior) || roles.contains(AppRole.housekeeping);
  }

  static Set<AppRole> fromRoleNames(Iterable<String> rawRoles) {
    return rawRoles.map((e) => _mapRole(e.toString())).whereType<AppRole>().toSet();
  }

  // --- Events
  static bool canViewEvents(Set<AppRole> roles) {
    // all authenticated users can view scheduled events
    return roles.isNotEmpty;
  }

  static bool canCreateEvent(Set<AppRole> roles) {
    return roles.contains(AppRole.admin) || roles.contains(AppRole.senior) || roles.contains(AppRole.housekeeping);
  }

  static bool canManageSessions(Set<AppRole> roles) {
    return roles.contains(AppRole.admin);
  }

  static bool canManageAnyEvent(Set<AppRole> roles) {
    return roles.contains(AppRole.admin) || roles.contains(AppRole.senior);
  }

  static bool isHousekeeping(Set<AppRole> roles) {
    return roles.contains(AppRole.housekeeping);
  }

  static bool canAccessOffice(Set<AppRole> roles) {
    return roles.contains(AppRole.admin) ||
        roles.contains(AppRole.senior) ||
        roles.contains(AppRole.housekeeping) ||
        roles.contains(AppRole.treasurer);
  }

  static bool canManageUsers(Set<AppRole> roles) {
    return roles.contains(AppRole.admin) || roles.contains(AppRole.senior);
  }

  static bool canManageCatalog(Set<AppRole> roles) {
    return roles.contains(AppRole.admin);
  }

  static bool canManageFines(Set<AppRole> roles) {
    return roles.contains(AppRole.admin) || roles.contains(AppRole.senior);
  }

  static bool canManagePeriods(Set<AppRole> roles) {
    return roles.contains(AppRole.admin);
  }

  // --- Tasks (who can see/edit/delete all)
  static bool canManageTasks(Set<AppRole> roles) {
    return roles.contains(AppRole.admin) ||
        roles.contains(AppRole.senior) ||
        roles.contains(AppRole.housekeeping);
  }
}