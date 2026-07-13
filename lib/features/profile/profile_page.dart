import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:jwt_decode/jwt_decode.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
import '../../auth/roles.dart';
import '../../common/cache/app_cache.dart';
import '../../common/platform/android_install_state.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../common/widgets/busy_icon_button.dart';
import '../../common/widgets/schnupfspruch_button.dart';
import '../../common/settings/app_settings_store.dart';
import '../../models/member_status.dart';
import 'dart:async';

class ProfilePage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;
  final bool showBottomNavigationBar;
  final String? locationOverride;

  const ProfilePage({
    super.key,
    required this.api,
    required this.authStore,
    this.showBottomNavigationBar = true,
    this.locationOverride,
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  static const _ttlProfile = Duration(minutes: 10);
  static const _kProfile = 'profile.snapshot';

  bool _loading = true;
  bool _refreshing = false;

  String _displayName = '—';
  String _username = '—';
  String _roleLabel = 'Mitglied';
  String _memberStatus = '';

  String _appVersion = '—';
  String _platformLabel = '—';
  String _deviceLabel = '—';
  String _sessionLabel = '—';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    try {
      unawaited(
        AppSettingsStore.I.syncWithBackend(
          widget.api,
          canSyncDevModeNotifyOnlyMe: widget.authStore.currentRoles.contains(
            AppRole.admin,
          ),
        ),
      );

      final c = await AppCache.I.entryOrLoadPersisted<_ProfileSnapshot>(
        _kProfile,
        decode: (json) =>
            _ProfileSnapshot.fromJson((json as Map).cast<String, dynamic>()),
      );
      final hasCache = c != null;

      if (hasCache && mounted) {
        _applySnapshot(c.value);
        setState(() => _loading = false);

        if (!force && c.isFresh(_ttlProfile)) return;
      }

      final showFullSpinner = !hasCache;
      if (mounted) {
        setState(() {
          _loading = showFullSpinner;
          _refreshing = !showFullSpinner;
        });
      }

      try {
        final snap = await _buildSnapshot(forceCurrentUserRefresh: force);

        await AppCache.I.setPersisted<_ProfileSnapshot>(
          _kProfile,
          snap,
          encode: (s) => s.toJson(),
        );

        if (!mounted) return;
        setState(() => _applySnapshot(snap));
      } catch (_) {
        // keep whatever is shown
      } finally {
        if (mounted) {
          setState(() {
            _loading = false;
            _refreshing = false;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  void _applySnapshot(_ProfileSnapshot s) {
    _displayName = s.displayName;
    _username = s.username;
    _roleLabel = s.roleLabel;
    _memberStatus = s.memberStatus;

    _appVersion = s.appVersion;
    _platformLabel = s.platformLabel;
    _deviceLabel = s.deviceLabel;
    _sessionLabel = s.sessionLabel;
  }

  Future<_ProfileSnapshot> _buildSnapshot({
    bool forceCurrentUserRefresh = false,
  }) async {
    final token = widget.authStore.accessToken ?? '';

    if (forceCurrentUserRefresh) {
      await widget.authStore.refreshMe(widget.api, force: true);
    } else {
      await widget.authStore.refreshMeIfStale(widget.api);
    }

    final roleLabel = _roleLabelFromRoleSet(widget.authStore.currentRoles);

    final sessionLabel = widget.authStore.isLoggedIn
        ? 'Angemeldet'
        : 'Nicht angemeldet';

    final pkg = await PackageInfo.fromPlatform();
    final appVersion = '${pkg.version} (${pkg.buildNumber})';

    final deviceInfo = DeviceInfoPlugin();
    final platformLabel = _computePlatformLabel();

    String deviceLabel = '—';
    if (kIsWeb) {
      final web = await deviceInfo.webBrowserInfo;
      final ua = (web.userAgent ?? '').trim();
      final parts = <String>[
        if (web.browserName.name.isNotEmpty) web.browserName.name,
        if (ua.isNotEmpty) 'UA: $ua',
      ];
      deviceLabel = parts.isEmpty ? '—' : parts.join(' • ');
    } else if (Platform.isAndroid) {
      final a = await deviceInfo.androidInfo;
      deviceLabel = '${a.manufacturer} ${a.model} (SDK ${a.version.sdkInt})';
    } else if (Platform.isIOS) {
      final i = await deviceInfo.iosInfo;
      deviceLabel = '${i.name} ${i.model} (${i.systemName} ${i.systemVersion})';
    } else if (Platform.isLinux) {
      final l = await deviceInfo.linuxInfo;
      deviceLabel = '${l.name} ${l.version}';
    } else if (Platform.isMacOS) {
      final m = await deviceInfo.macOsInfo;
      deviceLabel = '${m.computerName} (${m.osRelease})';
    } else if (Platform.isWindows) {
      final w = await deviceInfo.windowsInfo;
      deviceLabel = 'Windows (build ${w.buildNumber})';
    }

    String displayName = '—';
    String username = '—';
    String memberStatus = '';

    String? pickString(dynamic v) {
      final s = v?.toString().trim();
      return (s != null && s.isNotEmpty) ? s : null;
    }

    if (token.isNotEmpty) {
      try {
        final payload = Jwt.parseJwt(token);

        final dn =
            pickString(payload['displayName']) ??
            pickString(payload['display_name']) ??
            pickString(payload['name']);

        final un =
            pickString(payload['username']) ??
            pickString(payload['preferred_username']) ??
            pickString(payload['login']);

        final ms =
            pickString(payload['memberStatus']) ??
            pickString(payload['member_status']);

        if (dn != null) displayName = dn;
        if (un != null) username = un;
        if (ms != null) memberStatus = ms;

        final sub = pickString(payload['sub']);
        if (username == '—' && sub != null) {
          username = sub;
        }
      } catch (_) {
        // ignore
      }

      try {
        final me = await widget.api.getMe();

        final dn2 = me.displayName.trim();
        final un2 = me.username.trim();

        if (dn2.isNotEmpty) displayName = dn2;
        if (un2.isNotEmpty) username = un2;

        memberStatus = me.memberStatus;
      } catch (_) {
        // ignore
      }
    }

    return _ProfileSnapshot(
      displayName: displayName,
      username: username,
      roleLabel: roleLabel,
      memberStatus: memberStatus,
      sessionLabel: sessionLabel,
      appVersion: appVersion,
      platformLabel: platformLabel,
      deviceLabel: deviceLabel,
    );
  }

  static String _computePlatformLabel() {
    if (kIsWeb) return 'Web';
    try {
      if (Platform.isAndroid) return 'Android';
      if (Platform.isIOS) return 'iOS';
      if (Platform.isLinux) return 'Linux';
      if (Platform.isMacOS) return 'macOS';
      if (Platform.isWindows) return 'Windows';
      return 'Unknown';
    } catch (_) {
      return 'Unknown';
    }
  }

  static String _roleLabelFromRoleSet(Set<AppRole> roles) {
    final labels = <String>[
      if (roles.contains(AppRole.admin)) 'Admin',
      if (roles.contains(AppRole.senior)) 'Sprecher',
      if (roles.contains(AppRole.housekeeping)) 'Schmuckwart',
      if (roles.contains(AppRole.fechtwart)) 'Fechtwart',
      if (roles.contains(AppRole.treasurer)) 'Kassenwart',
    ];
    return labels.isEmpty ? 'Mitglied' : labels.join(', ');
  }

  Future<void> _openAppInfoSheet() async {
    final shouldLoadInstallState = !kIsWeb && Platform.isAndroid;
    AndroidInstallState? installState;
    var installStateUnavailable = false;

    if (shouldLoadInstallState) {
      try {
        installState = await AndroidInstallState.load();
        installStateUnavailable = installState == null;
      } catch (_) {
        installStateUnavailable = true;
      }
    }

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final cs = theme.colorScheme;

        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: 16 + MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              shrinkWrap: true,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: cs.primaryContainer,
                      foregroundColor: cs.onPrimaryContainer,
                      child: const Icon(Icons.info_outline_rounded),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'App-Informationen',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.info_outline_rounded),
                        title: const Text('App-Version'),
                        subtitle: Text(_appVersion),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.phone_android_rounded),
                        title: const Text('Plattform'),
                        subtitle: Text(_platformLabel),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.devices_other_rounded),
                        title: const Text('Gerät'),
                        subtitle: Text(_deviceLabel),
                      ),
                    ],
                  ),
                ),
                if (installState != null) ...[
                  const SizedBox(height: 8),
                  _AndroidInstallationInfoCard(state: installState),
                ] else if (installStateUnavailable) ...[
                  const SizedBox(height: 8),
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.warning_amber_rounded),
                      title: Text('Android-Installationsstatus'),
                      subtitle: Text(
                        'Die Installationsinformationen konnten nicht ausgelesen werden.',
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(sheetContext),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Fertig'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static bool _isStrongEnoughPassword(String s) {
    if (s.length < 8) return false;
    final hasUpper = RegExp(r'[A-Z]').hasMatch(s);
    final hasLower = RegExp(r'[a-z]').hasMatch(s);
    final hasDigit = RegExp(r'\d').hasMatch(s);
    return hasUpper && hasLower && hasDigit;
  }

  Future<void> _openChangePasswordDialog() async {
    final formKey = GlobalKey<FormState>();
    final newPwCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();

    bool submitting = false;
    bool showNew = false;
    bool showConfirm = false;

    Future<void> submit(StateSetter setStateDialog) async {
      if (submitting) return;
      if (!(formKey.currentState?.validate() ?? false)) return;

      setStateDialog(() => submitting = true);

      try {
        final me = await widget.api.getMe();
        await widget.api.patchUserPassword(
          userId: me.id,
          newPassword: newPwCtrl.text,
        );

        if (!mounted) return;
        Navigator.of(context).pop(true);

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Passwort geändert.')));
      } catch (_) {
        if (!mounted) return;
        Navigator.of(context).pop(false);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Passwort konnte nicht geändert werden.'),
          ),
        );
      } finally {
        if (Navigator.of(context).canPop()) {
          // dialog already popped in both paths
        } else {
          setStateDialog(() => submitting = false);
        }
      }
    }

    await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) => AlertDialog(
            title: const Text('Passwort ändern'),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Das Passwort sollte nur zu einem sicheren Passwort geändert werden.',
                            softWrap: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: newPwCtrl,
                      obscureText: !showNew,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Neues Passwort',
                        helperText:
                            'Mind. 8 Zeichen, Groß + Kleinbuchstaben, mind. eine Zahl.',
                        helperMaxLines: 3,
                        suffixIcon: IconButton(
                          tooltip: showNew ? 'Verbergen' : 'Anzeigen',
                          onPressed: () =>
                              setStateDialog(() => showNew = !showNew),
                          icon: Icon(
                            showNew
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                          ),
                        ),
                      ),
                      validator: (v) {
                        final s = (v ?? '').trim();
                        if (s.isEmpty) return 'Bitte Passwort eingeben.';
                        if (!_isStrongEnoughPassword(s)) {
                          return 'Zu schwach: mind. 8 Zeichen, Groß + Kleinbuchstaben, mind. eine Zahl.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: confirmCtrl,
                      obscureText: !showConfirm,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: 'Passwort wiederholen',
                        suffixIcon: IconButton(
                          tooltip: showConfirm ? 'Verbergen' : 'Anzeigen',
                          onPressed: () =>
                              setStateDialog(() => showConfirm = !showConfirm),
                          icon: Icon(
                            showConfirm
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                          ),
                        ),
                      ),
                      validator: (v) {
                        final s = (v ?? '');
                        if (s != newPwCtrl.text) {
                          return 'Passwörter stimmen nicht überein.';
                        }
                        return null;
                      },
                      onFieldSubmitted: (_) => submit(setStateDialog),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: submitting ? null : () => Navigator.pop(ctx, false),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: submitting ? null : () => submit(setStateDialog),
                child: submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Ändern'),
              ),
            ],
          ),
        );
      },
    );

    newPwCtrl.dispose();
    confirmCtrl.dispose();
  }

  Future<void> _logout() async {
    final rt = widget.authStore.refreshToken;
    if (rt != null && rt.isNotEmpty) {
      try {
        await widget.api.logoutOnServer(rt);
      } catch (_) {
        // ignore
      }
    }

    await widget.authStore.clearAllUserData();
    await AppSettingsStore.I.clearLocalSettings();
    await AppCache.I.clearPersisted();

    if (!mounted) return;
    context.go('/login');
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Abmelden?'),
        content: const Text(
          'Du wirst abgemeldet und lokale Daten werden gelöscht.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Abmelden'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Profil',
      showBottomNavigationBar: widget.showBottomNavigationBar,
      locationOverride: widget.locationOverride,
      onRefresh: () => _load(force: true),
      actions: [
        const SchnupfspruchButton(),
        BusyIconButton(
          busy: _loading || _refreshing,
          tooltip: 'Neu laden',
          icon: Icons.refresh_rounded,
          onPressed: () => _load(force: true),
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _loading
                  ? const Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Text('Lade Profil…'),
                      ],
                    )
                  : Row(
                      children: [
                        CircleAvatar(
                          radius: 26,
                          child: Text(
                            (_displayName != '—' &&
                                    _displayName.trim().isNotEmpty)
                                ? _displayName
                                      .trim()
                                      .characters
                                      .first
                                      .toUpperCase()
                                : 'V',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _displayName,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _username == '—' ? '—' : '@$_username',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(
                                    Icons.verified_user_rounded,
                                    size: 18,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _roleLabel,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.group_rounded,
                                    size: 18,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    MemberStatuses.label(_memberStatus),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.devices_rounded),
                  title: const Text('Sessions & Geräte'),
                  subtitle: Text(_sessionLabel),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/profile/sessions'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('App-Informationen'),
                  subtitle: Text(_appVersion),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _openAppInfoSheet,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.settings_rounded),
                  title: const Text('App-Einstellungen'),
                  subtitle: const Text(
                    'App-Verhalten und lokale Einstellungen',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/profile/app-settings'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: (_loading || !widget.authStore.isLoggedIn)
                  ? null
                  : _openChangePasswordDialog,
              icon: const Icon(Icons.password_rounded),
              label: const Text('Passwort ändern'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _confirmLogout,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Abmelden'),
            ),
          ),
          const SizedBox(height: 24),
          Text.rich(
            TextSpan(
              text: 'Verhåårm\n© ',
              style: Theme.of(context).textTheme.bodySmall,
              children: [
                TextSpan(
                  text: 'Valentin Schecklein',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    decoration: TextDecoration.underline,
                  ),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () async {
                      final uri = Uri.parse('https://github.com/herzblutnord');
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    },
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _AndroidInstallationInfoCard extends StatelessWidget {
  final AndroidInstallState state;

  const _AndroidInstallationInfoCard({required this.state});

  String _packageLabel(
    String? packageName, {
    String fallback = 'Nicht gesetzt',
  }) {
    if (packageName == null) return fallback;
    return packageName == state.packageName
        ? '$packageName (diese App)'
        : packageName;
  }

  String _permissionLabel({required bool declared, required bool granted}) {
    if (!declared) return 'Nicht deklariert';
    return granted ? 'Erteilt' : 'Nicht erteilt';
  }

  @override
  Widget build(BuildContext context) {
    final requiredTarget = state.requiredTargetSdkForSilentUpdate;
    final silentRequirements = state.meetsSilentSelfUpdateRequirements;

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              silentRequirements
                  ? Icons.verified_rounded
                  : Icons.info_outline_rounded,
            ),
            title: const Text('Prompt-freies Selbstupdate'),
            subtitle: Text(
              silentRequirements
                  ? 'Öffentliche Android-Voraussetzungen erfüllt. Android oder Play Protect kann trotzdem eine Bestätigung verlangen.'
                  : 'Voraussetzungen nicht vollständig erfüllt. Target SDK ${state.targetSdk}${requiredTarget == null ? '' : ' (benötigt: $requiredTarget)'} auf Android SDK ${state.sdkInt}.',
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.install_mobile_rounded),
            title: const Text('Registrierter Installer'),
            subtitle: Text(
              _packageLabel(
                state.installingPackageName,
                fallback: 'Nicht verfügbar (z. B. ADB/System-App)',
              ),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.admin_panel_settings_rounded),
            title: const Text('Update-Eigentümer'),
            subtitle: Text(
              state.sdkInt < 34
                  ? 'Von dieser Android-Version nicht unterstützt'
                  : _packageLabel(
                      state.updateOwnerPackageName,
                      fallback: 'Nicht gesetzt (Ownership nicht aktiv)',
                    ),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.source_rounded),
            title: const Text('Installationsquelle'),
            subtitle: Text(state.packageSourceLabel),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.playlist_add_check_circle_rounded),
            title: const Text('Installation initiiert durch'),
            subtitle: Text(
              _packageLabel(
                state.initiatingPackageName,
                fallback: 'Nicht verfügbar',
              ),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.android_rounded),
            title: const Text('Unbekannte Apps installieren'),
            subtitle: Text(
              !state.requestInstallPackagesDeclared
                  ? 'Nicht deklariert'
                  : state.canRequestPackageInstalls
                  ? 'Vom Benutzer erlaubt'
                  : 'Vom Benutzer nicht erlaubt',
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.system_update_alt_rounded),
            title: const Text('Updates ohne Benutzeraktion'),
            subtitle: Text(
              _permissionLabel(
                declared: state.updateWithoutUserActionDeclared,
                granted: state.updateWithoutUserActionGranted,
              ),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.verified_user_rounded),
            title: const Text('Update-Ownership anfordern'),
            subtitle: Text(
              state.sdkInt < 34
                  ? 'Von dieser Android-Version nicht unterstützt'
                  : _permissionLabel(
                      declared: state.enforceUpdateOwnershipDeclared,
                      granted: state.enforceUpdateOwnershipGranted,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileSnapshot {
  final String displayName;
  final String username;
  final String roleLabel;
  final String memberStatus;

  final String appVersion;
  final String platformLabel;
  final String deviceLabel;
  final String sessionLabel;

  const _ProfileSnapshot({
    required this.displayName,
    required this.username,
    required this.roleLabel,
    required this.memberStatus,
    required this.sessionLabel,
    required this.appVersion,
    required this.platformLabel,
    required this.deviceLabel,
  });

  Map<String, dynamic> toJson() => {
    'displayName': displayName,
    'username': username,
    'roleLabel': roleLabel,
    'memberStatus': memberStatus,
    'appVersion': appVersion,
    'platformLabel': platformLabel,
    'deviceLabel': deviceLabel,
    'sessionLabel': sessionLabel,
  };

  factory _ProfileSnapshot.fromJson(Map<String, dynamic> json) =>
      _ProfileSnapshot(
        displayName: (json['displayName'] as String?) ?? '—',
        username: (json['username'] as String?) ?? '—',
        roleLabel: (json['roleLabel'] as String?) ?? 'Mitglied',
        memberStatus: (json['memberStatus'] as String?) ?? '',
        sessionLabel: (json['sessionLabel'] as String?) ?? '—',
        appVersion: (json['appVersion'] as String?) ?? '—',
        platformLabel: (json['platformLabel'] as String?) ?? '—',
        deviceLabel: (json['deviceLabel'] as String?) ?? '—',
      );
}
