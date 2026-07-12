import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
import '../../auth/roles.dart';
import '../../common/settings/app_settings_store.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../update/web_app_refresh.dart';

class AppSettingsPage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;

  const AppSettingsPage({super.key, required this.api, required this.authStore});

  @override
  State<AppSettingsPage> createState() => _AppSettingsPageState();
}

class _AppSettingsPageState extends State<AppSettingsPage> {
  bool _forceReloadingWebApp = false;

  Future<void> _setHidePhilister(bool value) async {
    await AppSettingsStore.I.setHidePhilister(widget.api, value);
  }

  Future<void> _confirmForceReloadWebApp() async {
    if (!kIsWeb || _forceReloadingWebApp) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('App vollständig neu laden?'),
        content: const Text(
          'Dadurch wird der Browser-Cache der PWA geleert und die App neu vom Server geladen. '
          'Das hilft, wenn nach einem Update noch alte Funktionen angezeigt werden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Neu laden'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    if (!mounted) return;
    setState(() => _forceReloadingWebApp = true);

    try {
      await forceReloadWebApp();
    } catch (_) {
      if (!mounted) return;

      setState(() => _forceReloadingWebApp = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('App konnte nicht vollständig neu geladen werden.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.authStore.currentRoles.contains(AppRole.admin);

    return AppScaffold(
      title: 'Einstellungen',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                AnimatedBuilder(
                  animation: AppSettingsStore.I,
                  builder: (context, _) {
                    final selected =
                        AppSettingsStore.I.themeMode == ThemeMode.light
                        ? ThemeMode.light
                        : ThemeMode.dark;

                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.contrast_rounded),
                              const SizedBox(width: 16),
                              Text(
                                'Darstellung',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: SegmentedButton<ThemeMode>(
                              showSelectedIcon: false,
                              segments: const [
                                ButtonSegment<ThemeMode>(
                                  value: ThemeMode.dark,
                                  icon: Icon(Icons.dark_mode_rounded),
                                  label: Text('Dunkel'),
                                ),
                                ButtonSegment<ThemeMode>(
                                  value: ThemeMode.light,
                                  icon: Icon(Icons.light_mode_rounded),
                                  label: Text('Hell'),
                                ),
                              ],
                              selected: {selected},
                              onSelectionChanged: (selection) async {
                                await AppSettingsStore.I.setThemeMode(
                                  widget.api,
                                  selection.first,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                AnimatedBuilder(
                  animation: AppSettingsStore.I,
                  builder: (context, _) {
                    return SwitchListTile(
                      secondary: const Icon(Icons.group_off_rounded),
                      title: const Text(
                        'Philister in Auswahllisten ausblenden',
                      ),
                      subtitle: const Text(
                        'Gilt nur für Auswahlfenster, nicht für Berechtigungen.',
                      ),
                      value: AppSettingsStore.I.hidePhilister,
                      onChanged: _setHidePhilister,
                    );
                  },
                ),
                if (isAdmin) ...[
                  const Divider(height: 1),
                  AnimatedBuilder(
                    animation: AppSettingsStore.I,
                    builder: (context, _) {
                      return SwitchListTile(
                        secondary: const Icon(Icons.developer_mode_rounded),
                        title: const Text('Dev-Modus'),
                        subtitle: const Text(
                          'Beim Erstellen von Live-Events, Strafen und Arbeitsaufträgen Benachrichtigungen nur an mich senden.',
                        ),
                        value: AppSettingsStore.I.devModeNotifyOnlyMe,
                        onChanged: (value) async {
                          await AppSettingsStore.I.setDevModeNotifyOnlyMe(
                            widget.api,
                            value,
                          );
                        },
                      );
                    },
                  ),
                ],
                if (kIsWeb) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.restart_alt_rounded),
                    title: const Text('App vollständig neu laden'),
                    subtitle: const Text(
                      'Browser-Cache der App leeren, falls nach einem Update noch alte Inhalte erscheinen.',
                    ),
                    trailing: _forceReloadingWebApp
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chevron_right_rounded),
                    onTap: _forceReloadingWebApp
                        ? null
                        : _confirmForceReloadWebApp,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
