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
  static const int _maxPhotos = 5;

  bool _loading = true;

  FineDto? _fine;
  Map<String, UserPickerDto> _userById = const {};
  List<ConventPeriodDto> _periods = const [];
  Map<String, FineCatalogItemDto> _catalogById = const {};

  // Photos meta for UI (count + enable/disable buttons)
  bool _photosMetaLoading = false;
  int? _photoCount; // null while not loaded yet

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool _isAttendanceFine(FineDto f) {
    if (f.type != FineType.catalog) return false;
    final cid = (f.catalogItemId ?? '').trim();
    if (cid.isEmpty) return false;
    final title = (_catalogById[cid]?.title ?? '').trim().toLowerCase();
    return title == 'absent' || title == 'late';
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        widget.api.getFine(widget.fineId),
        widget.api.pickerUsers(),
        widget.api.listPeriods(),
        widget.api.listFineCatalog(active: null),
      ]);

      final fine = results[0] as FineDto;
      final users = results[1] as List<UserPickerDto>;
      final periods = (results[2] as List<ConventPeriodDto>).toList();
      final catalog = results[3] as List<FineCatalogItemDto>;

      final userById = {for (final u in users) u.id: u};
      final catalogById = {for (final c in catalog) c.id: c};

      if (!mounted) return;
      setState(() {
        _fine = fine;
        _userById = userById;
        _periods = periods;
        _catalogById = catalogById;
      });

      // load photo count in background after the main card content is ready
      await _loadPhotoCount();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Laden fehlgeschlagen: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadPhotoCount() async {
    final fine = _fine;
    if (fine == null) return;

    if (mounted) setState(() => _photosMetaLoading = true);
    try {
      final list = await widget.api.listFinePhotos(fine.id);
      if (!mounted) return;
      setState(() => _photoCount = list.length);
    } catch (_) {
      if (!mounted) return;
      setState(() => _photoCount = _photoCount ?? 0);
    } finally {
      if (mounted) setState(() => _photosMetaLoading = false);
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
        (a, b) => Format.parseIsoToLocal(
          b.startAt,
        ).compareTo(Format.parseIsoToLocal(a.startAt)),
      );
    return Format.findPeriodForFineDate(
      fineDate: f.fineDate,
      periods: periodsSorted,
    );
  }

  Future<void> _deleteFine() async {
    final fine = _fine;
    if (fine == null) return;

    final roles = widget.authStore.currentRoles;
    if (!Roles.canManageFines(roles)) return;

    // Attendance fines are system-generated and not deletable.
    if (_isAttendanceFine(fine)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Automatische Anwesenheits-Beihängungen können nicht gelöscht werden.',
          ),
        ),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Beihängung löschen?'),
        content: const Text('Dies kann nicht rückgängig gemacht werden.'),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Gelöscht.')));

      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/fines');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Löschen fehlgeschlagen: $e')));
    }
  }

  Future<void> _openGallery() async {
    final fine = _fine;
    if (fine == null) return;

    await FinePhotosDialog.openGallery(
      context: context,
      api: widget.api,
      authStore: widget.authStore,
      fineId: fine.id,
    );

    await _loadPhotoCount();
  }

  Future<void> _openAdd() async {
    final fine = _fine;
    if (fine == null) return;

    await FinePhotosDialog.openAdd(
      context: context,
      api: widget.api,
      authStore: widget.authStore,
      fineId: fine.id,
      maxPhotos: _maxPhotos,
      currentCount: _photoCount ?? 0,
    );

    await _loadPhotoCount();
  }

  @override
  Widget build(BuildContext context) {
    final roles = widget.authStore.currentRoles;

    final fine = _fine;
    final p = (fine == null) ? null : _periodForFine(fine);

    final canDelete =
        Roles.canManageFines(roles) && fine != null && !_isAttendanceFine(fine);

    final count = _photoCount ?? 0;
    final canView = !_photosMetaLoading && count > 0;
    final canAdd =
        Roles.canCreateOfficialFine(roles) &&
        !_photosMetaLoading &&
        count < _maxPhotos;

    return AppScaffold(
      title: 'Beihängung',
      onRefresh: _load,
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
                        if (_isAttendanceFine(fine)) ...[
                          const SizedBox(height: 8),
                          const Chip(
                            label: Text('Automatisch (Anwesenheit)'),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          'Betrag: ${Format.centsToEur(fine.amountCents ?? 0)}',
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Grund: ${(fine.reason ?? '').trim().isEmpty ? '—' : fine.reason!.trim()}',
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Beihängungsdatum: ${Format.dateOnlyShort(fine.fineDate)}',
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Erstellt: ${Format.dateTimeShort(fine.createdAt)}',
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
                        Text(
                          'Bbr.',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        for (final id in fine.targetUserIds)
                          Text('• ${_userLabel(id)}'),
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
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Fotos',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            if (_photosMetaLoading)
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            else
                              Chip(label: Text('$count/$_maxPhotos')),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Fotos sind optional. Du kannst mehrere aus der Galerie hochladen oder eins per Kamera.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: canView ? _openGallery : null,
                                icon: const Icon(Icons.photo_library_outlined),
                                label: Text(
                                  count > 0
                                      ? 'Fotos ansehen ($count)'
                                      : 'Fotos ansehen',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: canAdd ? _openAdd : null,
                                icon: const Icon(Icons.add_a_photo_outlined),
                                label: Text(
                                  canAdd
                                      ? 'Fotos hinzufügen'
                                      : 'Limit erreicht',
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (!canAdd)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              Roles.canCreateOfficialFine(roles)
                                  ? 'Upload-Limit erreicht (max. $_maxPhotos Fotos).'
                                  : 'Keine Berechtigung zum Hinzufügen.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
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
                        Text(
                          'Meta',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text('Semester: ${p?.semester ?? 'Unbekannt'}'),
                        const SizedBox(height: 8),
                        Text(
                          'Conventsperiode: ${p == null ? 'Unbekannt' : '${Format.dateShort(p.startAt)} – ${Format.dateShort(p.endAt)}'}',
                        ),
                        const SizedBox(height: 8),
                        Text('Ersteller: ${_userLabel(fine.creatorUserId)}'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
