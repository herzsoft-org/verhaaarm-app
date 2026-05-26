import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:verhaaarm/auth/roles.dart';

String _jwtWithPayload(Map<String, Object?> payload) {
  String encode(Object value) {
    return base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  }

  return '${encode({'alg': 'none', 'typ': 'JWT'})}.${encode(payload)}.';
}

void main() {
  group('Roles.fromAccessToken', () {
    test('returns an empty set for missing or invalid tokens', () {
      expect(Roles.fromAccessToken(null), isEmpty);
      expect(Roles.fromAccessToken(''), isEmpty);
      expect(Roles.fromAccessToken('not-a-jwt'), isEmpty);
    });

    test('maps role lists and ignores unknown roles', () {
      final roles = Roles.fromAccessToken(
        _jwtWithPayload({
          'roles': ['ADMIN', 'MEMBER', 'UNKNOWN'],
        }),
      );

      expect(roles, {AppRole.admin, AppRole.member});
    });

    test('maps a single role string', () {
      final roles = Roles.fromAccessToken(_jwtWithPayload({'roles': 'SENIOR'}));

      expect(roles, {AppRole.senior});
    });
  });

  group('role permissions', () {
    test('allows office access only for elevated roles', () {
      expect(Roles.canAccessOffice({AppRole.member}), isFalse);
      expect(Roles.canAccessOffice({AppRole.treasurer}), isTrue);
      expect(Roles.canAccessOffice({AppRole.housekeeping}), isTrue);
    });

    test('keeps admin-only permissions admin-only', () {
      expect(Roles.canManageCatalog({AppRole.senior}), isFalse);
      expect(Roles.canManageCatalog({AppRole.admin}), isTrue);
      expect(Roles.canManagePeriods({AppRole.housekeeping}), isFalse);
      expect(Roles.canManagePeriods({AppRole.admin}), isTrue);
    });
  });
}
