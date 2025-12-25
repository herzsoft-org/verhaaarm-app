import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
import '../../auth/roles.dart';
import '../../common/format.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../models/dtos.dart';

class FineDetailPage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;
  final String fineId;

  const FineDetailPage({super.key, required this.api, required this.authStore, required this.fineId});

  @override
  State<FineDetailPage> createState() => _FineDetailPageState();
}

class _FineDetailPageState extends State<FineDetailPage> {
  bool _loading = true;

  FineDto? _fine;
  Map<String, UserPickerDto> _userById = const {};
  Map<String, ConventPeriodDto> _periodById = const {};
  Map<String, FineCatalogItemDto> _catalogById = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final fine = await widget.api.getFine(widget.fineId);
      final users = await widget.api.pickerUsers();
      final periods = await widget.api.listPeriods();
      final catalog = await widget.api.listFineCatalog(active: null);

      final userById = {for (final u in users) u.id: u};
      final periodById = {for (final p in periods) p.id: p};
      final catalogById = {for (final c in catalog) c.id: c};

      if (!mounted) return;
      setState(() {
        _fine = fine;
        _userById = userById;
        _periodById = periodById;
        _catalogById = catalogById;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Laden fehlgeschlagen: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _userLabel(String id) => _userById[id]?.displayName ?? id;

  String _titleForFine(FineDto f) {
    if (f.type == FineType.catalog && f.catalogItemId != null) {
      final item = _catalogById[f.catalogItemId!];
      return item?.title ?? 'Beihängung';
    }
    return 'Beihängung';
  }


  Future<void> _deleteFine() async {
    final fine = _fine;
    if (fine == null) return;

    final roles = Roles.fromAccessToken(widget.authStore.accessToken);
    if (!Roles.canManageFines(roles)) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Beihängung löschen?'),
        content: const Text('Wird soft-deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await widget.api.deleteFine(fine.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gelöscht.')));
      context.go('/fines');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Löschen fehlgeschlagen: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final roles = Roles.fromAccessToken(widget.authStore.accessToken);
    final canDelete = Roles.canManageFines(roles);

    return AppScaffold(
      title: 'Beihängung',
      actions: [
        IconButton(
          tooltip: 'Neu laden',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loading ? null : _load,
        ),
        if (canDelete)
          IconButton(
            tooltip: 'Löschen',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: _loading ? null : _deleteFine,
          ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_fine == null)
          ? const Center(child: Text('Nicht gefunden.'))
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_titleForFine(_fine!), style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text('Betrag: ${Format.centsToEur(_fine!.amountCents ?? 0)}'),
                  const SizedBox(height: 8),
                  Text('Grund: ${(_fine!.reason ?? '').trim().isEmpty ? '—' : _fine!.reason!}'),
                  const SizedBox(height: 8),
                  Text('Erstellt: ${Format.dateTimeShort(_fine!.createdAt)}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Meta', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('Periode: ${_periodById[_fine!.periodId]?.semester ?? _fine!.periodId}'),
                  const SizedBox(height: 8),
                  Text('Ersteller: ${_userLabel(_fine!.creatorUserId)}'),
                  const SizedBox(height: 8),
                  if (_fine!.type == FineType.catalog && _fine!.catalogItemId != null)
                    Text('Katalog-ID: ${_fine!.catalogItemId}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ziele', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final id in _fine!.targetUserIds) Text('• ${_userLabel(id)}'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
