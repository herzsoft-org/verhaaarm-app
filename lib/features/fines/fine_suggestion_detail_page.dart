import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
import '../../common/format.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../models/dtos.dart';
import 'suggestion_photos_dialog.dart';

class FineSuggestionDetailPage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;
  final String suggestionId;

  const FineSuggestionDetailPage({
    super.key,
    required this.api,
    required this.authStore,
    required this.suggestionId,
  });

  @override
  State<FineSuggestionDetailPage> createState() => _FineSuggestionDetailPageState();
}

class _FineSuggestionDetailPageState extends State<FineSuggestionDetailPage> {
  static const int _maxPhotos = 5;

  bool _loading = true;
  bool _acting = false;
  bool _photosMetaLoading = false;

  FineSuggestionDto? _suggestion;
  Map<String, UserPickerDto> _userById = const {};
  Map<String, FineCatalogItemDto> _catalogById = const {};
  List<ConventPeriodDto> _periods = const [];

  int? _photoCount;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _isPending => (_suggestion?.status.toUpperCase() == 'PENDING');

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        widget.api.getSuggestion(widget.suggestionId),
        widget.api.pickerUsers(),
        widget.api.listFineCatalog(active: null),
        widget.api.listPeriods(),
      ]);

      final suggestion = results[0] as FineSuggestionDto;
      final users = results[1] as List<UserPickerDto>;
      final catalog = results[2] as List<FineCatalogItemDto>;
      final periods = results[3] as List<ConventPeriodDto>;

      if (!mounted) return;
      setState(() {
        _suggestion = suggestion;
        _userById = {for (final u in users) u.id: u};
        _catalogById = {for (final c in catalog) c.id: c};
        _periods = periods;
      });

      await _loadPhotoCount();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Vorschlag laden fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadPhotoCount() async {
    final s = _suggestion;
    if (s == null) return;

    if (mounted) setState(() => _photosMetaLoading = true);
    try {
      final list = await widget.api.listSuggestionPhotos(s.id);
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

  String _titleForSuggestion(FineSuggestionDto s) {
    if (s.type == FineType.catalog && s.catalogItemId != null) {
      final item = _catalogById[s.catalogItemId!];
      final t = (item?.title ?? '').trim();
      if (t.isNotEmpty) return t;
      return 'Katalog-Beihängung';
    }

    final r = (s.reason ?? '').trim();
    if (r.isNotEmpty) return r;

    return 'Beihängungsvorschlag';
  }

  String _statusLabel(String status) {
    switch (status.toUpperCase()) {
      case 'PENDING':
        return 'Offen';
      case 'ACCEPTED':
        return 'Angenommen';
      case 'REJECTED':
        return 'Abgelehnt';
      default:
        return status;
    }
  }

  ConventPeriodDto? _periodForSuggestion(FineSuggestionDto s) {
    final periodsSorted = [..._periods]
      ..sort((a, b) => b.startDateLocal.compareTo(a.startDateLocal));

    return Format.findPeriodForFineDate(
      fineDate: s.fineDate,
      periods: periodsSorted,
    );
  }

  Future<void> _withdraw() async {
    final s = _suggestion;
    if (s == null || !_isPending || _acting) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vorschlag zurückziehen?'),
        content: const Text('Der Vorschlag wird gelöscht.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Zurückziehen'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _acting = true);
    try {
      await widget.api.deleteSuggestion(s.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vorschlag zurückgezogen.')),
      );

      if (context.canPop()) {
        context.pop(true);
      } else {
        context.go('/my-fine-suggestions');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Zurückziehen fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _openGallery() async {
    final s = _suggestion;
    if (s == null) return;

    await SuggestionPhotosDialog.openGallery(
      context: context,
      api: widget.api,
      suggestionId: s.id,
      maxPhotos: _maxPhotos,
      canDelete: _isPending,
    );

    await _loadPhotoCount();
  }

  Future<void> _openAdd() async {
    final s = _suggestion;
    if (s == null || !_isPending) return;

    await SuggestionPhotosDialog.openAdd(
      context: context,
      api: widget.api,
      suggestionId: s.id,
      maxPhotos: _maxPhotos,
      currentCount: _photoCount ?? 0,
    );

    await _loadPhotoCount();
  }

  @override
  Widget build(BuildContext context) {
    final s = _suggestion;
    final p = s == null ? null : _periodForSuggestion(s);

    final count = _photoCount ?? 0;
    final canView = !_photosMetaLoading && count > 0;
    final canAdd = _isPending && !_photosMetaLoading && count < _maxPhotos;

    return AppScaffold(
      title: 'Beihängungsvorschlag',
      showNotificationButton: false,
      showProfileButton: false,
      actions: [
        IconButton(
          tooltip: 'Neu laden',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: (_loading || _acting) ? null : _load,
        ),
        if (_isPending)
          IconButton(
            tooltip: 'Bearbeiten',
            icon: const Icon(Icons.edit_outlined),
            onPressed: (_loading || _acting || s == null)
                ? null
                : () => context.push('/suggestions/${s.id}/edit'),
          ),
        if (_isPending)
          IconButton(
            tooltip: 'Zurückziehen',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: (_loading || _acting) ? null : _withdraw,
          ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (s == null)
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
                    _titleForSuggestion(s),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(label: Text(_statusLabel(s.status))),
                      if (_isPending)
                        const Chip(label: Text('Bearbeitbar')),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text('Betrag: ${Format.centsToEur(s.amountCents ?? 0)}'),
                  const SizedBox(height: 8),
                  Text(
                    'Grund: ${(s.reason ?? '').trim().isEmpty ? '—' : s.reason!.trim()}',
                  ),
                  const SizedBox(height: 8),
                  Text('Beihängungsdatum: ${Format.dateOnlyShort(s.fineDate)}'),
                  const SizedBox(height: 8),
                  Text('Erstellt: ${Format.dateTimeShort(s.createdAt)}'),
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
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Chip(label: Text('$count/$_maxPhotos')),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _isPending
                        ? 'Fotos können solange der Vorschlag offen ist hinzugefügt oder gelöscht werden.'
                        : 'Fotos können hier weiterhin angesehen werden.',
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
                            count > 0 ? 'Fotos ansehen ($count)' : 'Fotos ansehen',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: canAdd ? _openAdd : null,
                          icon: const Icon(Icons.add_a_photo_outlined),
                          label: Text(canAdd ? 'Fotos hinzufügen' : 'Nicht möglich'),
                        ),
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
                    'Conventsperiode: ${p == null ? 'Unbekannt' : '${Format.dateShort(p.startAt)} – ${Format.dateShort(p.endAt)}'}',
                  ),
                  const SizedBox(height: 8),
                  Text('Vorschlag von: ${_userLabel(s.creatorUserId)}'),
                  const SizedBox(height: 8),
                  if (s.type == FineType.catalog && s.catalogItemId != null)
                    Text('Katalog-ID: ${s.catalogItemId}'),
                  if (s.acceptedFineId != null &&
                      s.acceptedFineId!.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Angenommene Fine-ID: ${s.acceptedFineId}'),
                  ],
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
                  for (final id in s.targetUserIds) Text('• ${_userLabel(id)}'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}