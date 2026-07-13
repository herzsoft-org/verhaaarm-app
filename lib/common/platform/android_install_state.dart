import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AndroidInstallState {
  static const _platform = MethodChannel('verhaaarm.ota');

  final String packageName;
  final int sdkInt;
  final int targetSdk;
  final bool canRequestPackageInstalls;
  final bool requestInstallPackagesDeclared;
  final bool updateWithoutUserActionDeclared;
  final bool updateWithoutUserActionGranted;
  final bool enforceUpdateOwnershipDeclared;
  final bool enforceUpdateOwnershipGranted;
  final String? installingPackageName;
  final String? initiatingPackageName;
  final String? originatingPackageName;
  final String? updateOwnerPackageName;
  final int? packageSource;

  const AndroidInstallState({
    required this.packageName,
    required this.sdkInt,
    required this.targetSdk,
    required this.canRequestPackageInstalls,
    required this.requestInstallPackagesDeclared,
    required this.updateWithoutUserActionDeclared,
    required this.updateWithoutUserActionGranted,
    required this.enforceUpdateOwnershipDeclared,
    required this.enforceUpdateOwnershipGranted,
    required this.installingPackageName,
    required this.initiatingPackageName,
    required this.originatingPackageName,
    required this.updateOwnerPackageName,
    required this.packageSource,
  });

  static Future<AndroidInstallState?> load() async {
    if (kIsWeb || !Platform.isAndroid) return null;

    final raw = await _platform.invokeMapMethod<String, dynamic>(
      'getInstallState',
    );
    return raw == null ? null : AndroidInstallState.fromMap(raw);
  }

  factory AndroidInstallState.fromMap(Map<String, dynamic> map) {
    String? nullableString(Object? value) {
      final text = value?.toString().trim();
      return text == null || text.isEmpty ? null : text;
    }

    return AndroidInstallState(
      packageName: map['packageName']?.toString() ?? '',
      sdkInt: (map['sdkInt'] as num?)?.toInt() ?? 0,
      targetSdk: (map['targetSdk'] as num?)?.toInt() ?? 0,
      canRequestPackageInstalls:
          map['canRequestPackageInstalls'] as bool? ?? false,
      requestInstallPackagesDeclared:
          map['requestInstallPackagesDeclared'] as bool? ?? false,
      updateWithoutUserActionDeclared:
          map['updateWithoutUserActionDeclared'] as bool? ?? false,
      updateWithoutUserActionGranted:
          map['updateWithoutUserActionGranted'] as bool? ?? false,
      enforceUpdateOwnershipDeclared:
          map['enforceUpdateOwnershipDeclared'] as bool? ?? false,
      enforceUpdateOwnershipGranted:
          map['enforceUpdateOwnershipGranted'] as bool? ?? false,
      installingPackageName: nullableString(map['installingPackageName']),
      initiatingPackageName: nullableString(map['initiatingPackageName']),
      originatingPackageName: nullableString(map['originatingPackageName']),
      updateOwnerPackageName: nullableString(map['updateOwnerPackageName']),
      packageSource: (map['packageSource'] as num?)?.toInt(),
    );
  }

  bool get installerIsSelf => installingPackageName == packageName;
  bool get updateOwnerIsSelf => updateOwnerPackageName == packageName;

  int? get requiredTargetSdkForSilentUpdate {
    if (sdkInt < 31) return null;
    if (sdkInt <= 32) return 29;
    if (sdkInt == 33) return 30;
    if (sdkInt == 34) return 31;
    if (sdkInt == 35) return 33;
    return sdkInt - 2;
  }

  bool get meetsSilentSelfUpdateRequirements {
    final requiredTarget = requiredTargetSdkForSilentUpdate;
    return requiredTarget != null &&
        targetSdk >= requiredTarget &&
        canRequestPackageInstalls &&
        requestInstallPackagesDeclared &&
        updateWithoutUserActionDeclared &&
        updateWithoutUserActionGranted;
  }

  String get packageSourceLabel => switch (packageSource) {
    0 => 'Nicht angegeben',
    1 => 'Andere Quelle',
    2 => 'App-Store',
    3 => 'Lokale Datei',
    4 => 'Heruntergeladene Datei',
    _ => 'Nicht verfügbar',
  };
}
