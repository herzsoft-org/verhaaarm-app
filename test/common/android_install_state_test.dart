import 'package:flutter_test/flutter_test.dart';
import 'package:verhaaarm/common/platform/android_install_state.dart';

AndroidInstallState _state({
  int sdkInt = 36,
  int targetSdk = 36,
  bool canRequestPackageInstalls = true,
  bool updatePermissionGranted = true,
}) {
  return AndroidInstallState(
    packageName: 'moe.herz.verhaaarm',
    sdkInt: sdkInt,
    targetSdk: targetSdk,
    canRequestPackageInstalls: canRequestPackageInstalls,
    requestInstallPackagesDeclared: true,
    updateWithoutUserActionDeclared: true,
    updateWithoutUserActionGranted: updatePermissionGranted,
    enforceUpdateOwnershipDeclared: true,
    enforceUpdateOwnershipGranted: true,
    installingPackageName: 'moe.herz.verhaaarm',
    initiatingPackageName: 'moe.herz.verhaaarm',
    originatingPackageName: null,
    updateOwnerPackageName: null,
    packageSource: 2,
  );
}

void main() {
  test('maps current Android silent-update target SDK requirements', () {
    expect(_state(sdkInt: 30).requiredTargetSdkForSilentUpdate, isNull);
    expect(_state(sdkInt: 31).requiredTargetSdkForSilentUpdate, 29);
    expect(_state(sdkInt: 33).requiredTargetSdkForSilentUpdate, 30);
    expect(_state(sdkInt: 34).requiredTargetSdkForSilentUpdate, 31);
    expect(_state(sdkInt: 35).requiredTargetSdkForSilentUpdate, 33);
    expect(_state(sdkInt: 36).requiredTargetSdkForSilentUpdate, 34);
  });

  test(
    'reports whether public prompt-free self-update requirements are met',
    () {
      expect(_state().meetsSilentSelfUpdateRequirements, isTrue);
      expect(_state(targetSdk: 33).meetsSilentSelfUpdateRequirements, isFalse);
      expect(
        _state(
          canRequestPackageInstalls: false,
        ).meetsSilentSelfUpdateRequirements,
        isFalse,
      );
      expect(
        _state(
          updatePermissionGranted: false,
        ).meetsSilentSelfUpdateRequirements,
        isFalse,
      );
    },
  );

  test('parses package ownership and source information', () {
    final state = AndroidInstallState.fromMap({
      'packageName': 'moe.herz.verhaaarm',
      'sdkInt': 36,
      'targetSdk': 36,
      'canRequestPackageInstalls': true,
      'requestInstallPackagesDeclared': true,
      'updateWithoutUserActionDeclared': true,
      'updateWithoutUserActionGranted': true,
      'enforceUpdateOwnershipDeclared': true,
      'enforceUpdateOwnershipGranted': true,
      'installingPackageName': 'moe.herz.verhaaarm',
      'initiatingPackageName': 'moe.herz.verhaaarm',
      'updateOwnerPackageName': 'moe.herz.verhaaarm',
      'packageSource': 2,
    });

    expect(state.installerIsSelf, isTrue);
    expect(state.updateOwnerIsSelf, isTrue);
    expect(state.packageSourceLabel, 'App-Store');
  });
}
