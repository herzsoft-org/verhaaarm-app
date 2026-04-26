import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../api/api_client.dart';
import '../../../auth/auth_store.dart';
import '../../../auth/roles.dart';
import '../../../common/format.dart';
import '../../../common/widgets/app_scaffold.dart';
import '../../../models/dtos.dart';

class CatalogPage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;

  const CatalogPage({super.key, required this.api, required this.authStore});

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  bool _loading = true;
  List<FineCatalogItemDto> _items = const [];

  // IDs of system attendance catalog items from /attendance-fines
  Set<String> _systemIds = const {};

  bool _isSystemItem(FineCatalogItemDto it) => _systemIds.contains(it.id);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        widget.api.listFineCatalog(active: null),
        widget.api.getAttendanceFineConfig(),
      ]);

      final items = results[0] as List<FineCatalogItemDto>;
      final cfg = results[1] as AttendanceFineConfigDto;

      final sys = <String>{};
      final lateId = (cfg.lateCatalogItemId ?? '').trim();
      final absentId = (cfg.absentCatalogItemId ?? '').trim();
      if (lateId.isNotEmpty) sys.add(lateId);
      if (absentId.isNotEmpty) sys.add(absentId);

      // Sort: system items first, then alphabetical
      items.sort((a, b) {
        final as = sys.contains(a.id);
        final bs = sys.contains(b.id);
        if (as != bs) return as ? -1 : 1;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });

      if (!mounted) return;
      setState(() {
        _systemIds = sys;
        _items = items;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Katalog laden fehlgeschlagen: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCreateItem() async {
    final changed = await context.push<bool>('/office/catalog/new');
    if (changed == true && mounted) {
      await _load(force: true);
    }
  }

  Future<void> _openEditItem(FineCatalogItemDto it) async {
    final changed = await context.push<bool>('/office/catalog/${it.id}/edit');
    if (changed == true && mounted) {
      await _load(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roles = Roles.fromAccessToken(widget.authStore.accessToken);
    final can = Roles.canManageCatalog(roles);

    return AppScaffold(
      title: 'Beihängungskatalog',
      showNotificationButton: false,
      showProfileButton: false,
      actions: [
        IconButton(
          tooltip: 'Neu laden',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loading ? null : () => _load(force: true),
        ),
        if (can)
          IconButton(
            tooltip: 'Neuer Eintrag',
            icon: const Icon(Icons.add_rounded),
            onPressed: _openCreateItem,
          ),
      ],
      body: !can
          ? const Center(child: Text('Keine Berechtigung.'))
          : _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Keine Katalogeinträge gefunden.'),
            ),
          for (final it in _items)
            Card(
              child: ListTile(
                leading: _isSystemItem(it)
                    ? const Icon(Icons.lock_rounded)
                    : Icon(it.active ? Icons.check_circle_rounded : Icons.remove_circle_rounded),
                title: Row(
                  children: [
                    Expanded(child: Text(it.title)),
                    if (_isSystemItem(it))
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Chip(
                          label: Text('System'),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                        ),
                      ),
                  ],
                ),
                subtitle: Text(
                  'Default: ${Format.centsToEur(it.defaultAmountCents ?? 0)}'
                      '${_isSystemItem(it) ? '\nAutomatisch (Anwesenheit) – nur Betrag änderbar' : ''}'
                      '${it.active ? '' : '\nInaktiv'}',
                ),
                isThreeLine: _isSystemItem(it) || !it.active,
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _openEditItem(it),
              ),
            ),
        ],
      ),
    );
  }
}
