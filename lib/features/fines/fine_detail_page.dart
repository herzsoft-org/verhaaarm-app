import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
import '../../auth/roles.dart';
import '../../common/format.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../models/dtos.dart';
import 'fine_photos_dialog.dart';

class FineDetailPage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;
  final String fineId;

  const FineDetailPage({
    super.key,
    required this.api,
    required this.authStore,
    required this.fineId,
  });

  @override
  State<FineDetailPage> createState() => _FineDetailPageState();
}

class _FineDetailPageState extends State<FineDetailPage> {
  bool _loading = true;

  FineDto? _fine;
  Map<String, UserPickerDto> _userById = const {};
  List<ConventPeriodDto> _periods = const []; // <-- was const {} (wrong type)
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

      final periods = (await widget.api.listPeriods()).toList();
      final catalog = await widget.api.listFineCatalog(active: null);

      final userById = {for (final u in users) u.id: u};
      final catalogById = {for (final c in catalog) c.id: c};

      if (!mounted) return;
      setState(() {
        _fine = fine;
        _userById = userById;
        _periods = periods;
        _catalogById = catalogById;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Laden fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _userLabel(String id) => _userById[id]?.displayName ?? id;

  String _titleForFine(FineDto f) {
    if (f.type == FineType.catalog && f.catalogItemId != null) {
      final item = _catalogById[f.catalogItemId!];
      final t = (item?.title ?? '').trim();
      if (t.isNotEmpty) return t;
    }
    final r = (f.reason ?? '').trim();
    if (r.isNotEmpty) return r;
    return 'Beihängung';
  }

  ConventPeriodDto? _periodForFine(FineDto f) {
    final periodsSorted = [..._periods]
      ..sort(
            (a, b) => Format.parseIsoToLocal(b.startAt).compareTo(
          Format.parseIsoToLocal(a.startAt),
        ),
      );
    return Format.findPeriodForFineDate(
      fineDate: f.fineDate,
      periods: periodsSorted,
    );
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
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await widget.api.deleteFine(fine.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gelöscht.')),
      );

      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/fines');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Löschen fehlgeschlagen: $e')),
      );
    }
  }

  Future<void> _openPhotos() async {
    final fine = _fine;
    if (fine == null) return;

    await FinePhotosDialog.open(
      context: context,
      api: widget.api,
      authStore: widget.authStore,
      fineId: fine.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final roles = Roles.fromAccessToken(widget.authStore.accessToken);
    final canDelete = Roles.canManageFines(roles);

    final fine = _fine;
    final p = (fine == null) ? null : _periodForFine(fine);

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
          : (fine == null)
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
                  Text(
                    _titleForFine(fine),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text('Betrag: ${Format.centsToEur(fine.amountCents ?? 0)}'),
                  const SizedBox(height: 8),
                  Text(
                    'Grund: ${(fine.reason ?? '').trim().isEmpty ? '—' : fine.reason!.trim()}',
                  ),
                  const SizedBox(height: 8),
                  Text('Beihängungsdatum: ${Format.dateOnlyShort(fine.fineDate)}'),
                  const SizedBox(height: 8),
                  Text('Erstellt: ${Format.dateTimeShort(fine.createdAt)}'),
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
                  Text('Fotos', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  Text(
                    'Fotos sind optional. Du kannst mehrere aus der Galerie hochladen oder eins per Kamera.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: _openPhotos,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Fotos ansehen / hinzufügen'),
                      ),
                    ],
                  ),
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
                  Text('Semester: ${p?.semester ?? 'Unbekannt'}'),
                  const SizedBox(height: 8),
                  Text(
                    'Periode: ${p == null ? 'Unbekannt' : '${Format.dateShort(p.startAt)} – ${Format.dateShort(p.endAt)}'}',
                  ),
                  const SizedBox(height: 8),
                  Text('Ersteller: ${_userLabel(fine.creatorUserId)}'),
                  const SizedBox(height: 8),
                  if (fine.type == FineType.catalog && fine.catalogItemId != null)
                    Text('Katalog-ID: ${fine.catalogItemId}'),
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
                  Text('Bbr.', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final id in fine.targetUserIds) Text('• ${_userLabel(id)}'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
