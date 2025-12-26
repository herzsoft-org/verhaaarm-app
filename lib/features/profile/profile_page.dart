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
import '../../common/widgets/app_scaffold.dart';

class ProfilePage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;

  const ProfilePage({super.key, required this.api, required this.authStore});

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
  String _roleLabel = 'Member';

  String _appVersion = '—';
  String _platformLabel = '—';
  String _deviceLabel = '—';
  String _localeLabel = '—';
  String _sessionLabel = '—';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    try {
      final c = await AppCache.I.entryOrLoadPersisted<_ProfileSnapshot>(
        _kProfile,
        decode: (json) => _ProfileSnapshot.fromJson((json as Map).cast<String, dynamic>()),
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
        final snap = await _buildSnapshot();

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

    _appVersion = s.appVersion;
    _platformLabel = s.platformLabel;
    _deviceLabel = s.deviceLabel;
    _localeLabel = s.localeLabel;
    _sessionLabel = s.sessionLabel;
  }

  Future<_ProfileSnapshot> _buildSnapshot() async {
    final token = widget.authStore.accessToken ?? '';

    final roleSet = Roles.fromAccessToken(token);
    final roleLabel = _roleLabelFromRoleSet(roleSet);

    final sessionLabel = widget.authStore.isLoggedIn ? 'Angemeldet' : 'Nicht angemeldet';

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

    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    final localeLabel = '${locale.languageCode}_${locale.countryCode ?? ''}'.trim();

    String displayName = '—';
    String username = '—';

    String? pickString(dynamic v) {
      final s = v?.toString().trim();
      return (s != null && s.isNotEmpty) ? s : null;
    }

    // 1) Best-effort from JWT (may be minimal for members)
    if (token.isNotEmpty) {
      try {
        final payload = Jwt.parseJwt(token);

        final dn = pickString(payload['displayName']) ??
            pickString(payload['display_name']) ??
            pickString(payload['name']);

        final un = pickString(payload['username']) ??
            pickString(payload['preferred_username']) ??
            pickString(payload['login']);

        if (dn != null) displayName = dn;
        if (un != null) username = un;

        // Your backend sets subject=username. If the JWT doesn't contain a username claim,
        // fall back to 'sub' as the username (common pattern).
        final sub = pickString(payload['sub']);
        if (username == '—' && sub != null) {
          username = sub;
        }
      } catch (_) {
        // ignore
      }
    }

    // 2) Authoritative fallback: GET /users/me (works for all authenticated users)
    if (token.isNotEmpty && (displayName == '—' || username == '—')) {
      try {
        // Expect ApiClient to have a method for this endpoint.
        // If your ApiClient doesn't yet, add: getMe() -> GET /users/me
        final me = await widget.api.getMe();

        final dn2 = me.displayName.trim();
        final un2 = me.username.trim();

        if (displayName == '—' && dn2.isNotEmpty) displayName = dn2;
        if (username == '—' && un2.isNotEmpty) username = un2;
      } catch (_) {
        // ignore
      }
    }

    return _ProfileSnapshot(
      displayName: displayName,
      username: username,
      roleLabel: roleLabel,
      sessionLabel: sessionLabel,
      appVersion: appVersion,
      platformLabel: platformLabel,
      deviceLabel: deviceLabel,
      localeLabel: localeLabel,
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
    if (roles.contains(AppRole.admin)) return 'Admin';
    if (roles.contains(AppRole.senior)) return 'Senior';
    if (roles.contains(AppRole.treasurer)) return 'Treasurer';
    if (roles.contains(AppRole.housekeeping)) return 'Housekeeping';
    return 'Member';
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

    // Clear ALL persisted and in-memory cache on logout (prevents cross-user leakage).
    await AppCache.I.clearPersisted();

    if (!mounted) return;
    context.go('/login');
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Abmelden?'),
        content: const Text('Du wirst abgemeldet und lokale Daten werden gelöscht.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Abmelden')),
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
      actions: [
        IconButton(
          tooltip: 'Neu laden',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loading ? null : () => _load(force: true),
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: LinearProgressIndicator(),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _loading
                  ? const Row(
                children: [
                  SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 12),
                  Text('Lade Profil…'),
                ],
              )
                  : Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    child: Text(
                      (_displayName != '—' && _displayName.trim().isNotEmpty)
                          ? _displayName.trim().characters.first.toUpperCase()
                          : 'V',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_displayName, style: Theme.of(context).textTheme.titleLarge),
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
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(_roleLabel, style: Theme.of(context).textTheme.bodyMedium),
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
                  leading: const Icon(Icons.login_rounded),
                  title: const Text('Session'),
                  subtitle: Text(_sessionLabel),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('App'),
                  subtitle: Text(_appVersion),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.devices_rounded),
                  title: const Text('Gerät'),
                  subtitle: Text(_deviceLabel),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.public_rounded),
                  title: const Text('Plattform / Locale'),
                  subtitle: Text('$_platformLabel • $_localeLabel'),
                ),
              ],
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
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
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

class _ProfileSnapshot {
  final String displayName;
  final String username;
  final String roleLabel;

  final String appVersion;
  final String platformLabel;
  final String deviceLabel;
  final String localeLabel;
  final String sessionLabel;

  const _ProfileSnapshot({
    required this.displayName,
    required this.username,
    required this.roleLabel,
    required this.sessionLabel,
    required this.appVersion,
    required this.platformLabel,
    required this.deviceLabel,
    required this.localeLabel,
  });

  Map<String, dynamic> toJson() => {
    'displayName': displayName,
    'username': username,
    'roleLabel': roleLabel,
    'appVersion': appVersion,
    'platformLabel': platformLabel,
    'deviceLabel': deviceLabel,
    'localeLabel': localeLabel,
    'sessionLabel': sessionLabel,
  };

  factory _ProfileSnapshot.fromJson(Map<String, dynamic> json) => _ProfileSnapshot(
    displayName: (json['displayName'] as String?) ?? '—',
    username: (json['username'] as String?) ?? '—',
    roleLabel: (json['roleLabel'] as String?) ?? 'Member',
    sessionLabel: (json['sessionLabel'] as String?) ?? '—',
    appVersion: (json['appVersion'] as String?) ?? '—',
    platformLabel: (json['platformLabel'] as String?) ?? '—',
    deviceLabel: (json['deviceLabel'] as String?) ?? '—',
    localeLabel: (json['localeLabel'] as String?) ?? '—',
  );
}
