// lib/features/profile/profile_page.dart
import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:jwt_decode/jwt_decode.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
import '../../auth/roles.dart';
import '../../common/widgets/app_scaffold.dart';

class ProfilePage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;

  const ProfilePage({super.key, required this.api, required this.authStore});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _loading = true;

  // User identity
  String _displayName = '—';
  String _username = '—';
  String _roleLabel = 'Member';

  // Support info
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

  Future<void> _load() async {
    setState(() => _loading = true);

    try {
      final token = widget.authStore.accessToken;

      // --- roles (your implementation returns Set<AppRole>)
      final roleSet = Roles.fromAccessToken(token);
      _roleLabel = _roleLabelFromRoleSet(roleSet);

      // --- minimal session info
      _sessionLabel = widget.authStore.isLoggedIn ? 'Angemeldet' : 'Nicht angemeldet';

      // --- app info
      final pkg = await PackageInfo.fromPlatform();
      _appVersion = '${pkg.version} (${pkg.buildNumber})';

      // --- device info (no extra permissions)
      final deviceInfo = DeviceInfoPlugin();
      _platformLabel = _computePlatformLabel();

      if (kIsWeb) {
        final web = await deviceInfo.webBrowserInfo;
        final ua = (web.userAgent ?? '').trim();
        _deviceLabel = [
          if (web.browserName.name.isNotEmpty) web.browserName.name,
          if (ua.isNotEmpty) 'UA: $ua',
        ].join(' • ');
        if (_deviceLabel.isEmpty) _deviceLabel = '—';
      } else if (Platform.isAndroid) {
        final a = await deviceInfo.androidInfo;
        _deviceLabel = '${a.manufacturer} ${a.model} (SDK ${a.version.sdkInt})';
      } else if (Platform.isIOS) {
        final i = await deviceInfo.iosInfo;
        _deviceLabel = '${i.name} ${i.model} (${i.systemName} ${i.systemVersion})';
      } else if (Platform.isLinux) {
        final l = await deviceInfo.linuxInfo;
        _deviceLabel = '${l.name} ${l.version}';
      } else if (Platform.isMacOS) {
        final m = await deviceInfo.macOsInfo;
        _deviceLabel = '${m.computerName} (${m.osRelease})';
      } else if (Platform.isWindows) {
        final w = await deviceInfo.windowsInfo;
        _deviceLabel = 'Windows (build ${w.buildNumber})';
      } else {
        _deviceLabel = '—';
      }

      final locale = WidgetsBinding.instance.platformDispatcher.locale;
      _localeLabel = '${locale.languageCode}_${locale.countryCode ?? ''}'.trim();

      // --- identity: best-effort from token, otherwise try GET /users/{id}
      if (token != null && token.isNotEmpty) {
        try {
          final payload = Jwt.parseJwt(token);

          if (kDebugMode) {
            // ignore: avoid_print
            print('JWT payload: $payload');
          }

          // Try common claim names (adjust after you see payload)
          String? pickString(dynamic v) {
            final s = v?.toString().trim();
            return (s != null && s.isNotEmpty) ? s : null;
          }

          final dn = pickString(payload['displayName']) ??
              pickString(payload['display_name']) ??
              pickString(payload['name']);

          final un = pickString(payload['username']) ??
              pickString(payload['preferred_username']) ??
              pickString(payload['login']);

          if (dn != null) _displayName = dn;
          if (un != null) _username = un;

          // Try to find a UUID user id from several keys
          final idCandidate = pickString(payload['userId']) ??
              pickString(payload['user_id']) ??
              pickString(payload['id']) ??
              pickString(payload['uid']) ??
              pickString(payload['sub']);

          final userId = (idCandidate != null && _looksLikeUuid(idCandidate)) ? idCandidate : null;

          if (userId != null && (_displayName == '—' || _username == '—')) {
            try {
              final u = await widget.api.getUser(userId);
              if (u.displayName.trim().isNotEmpty) _displayName = u.displayName.trim();
              if (u.username.trim().isNotEmpty) _username = u.username.trim();
            } catch (_) {
              // ignore
            }
          }
        } catch (_) {
          // ignore
        }
      }

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  static bool _looksLikeUuid(String s) {
    final re = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    return re.hasMatch(s);
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
    // Adjust ordering to your desired “level” display
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
                        Text('@$_username', style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.verified_user_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
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
