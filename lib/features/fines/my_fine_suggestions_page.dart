import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../common/format.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../models/dtos.dart';

class MyFineSuggestionsPage extends StatefulWidget {
  final ApiClient api;

  const MyFineSuggestionsPage({
    super.key,
    required this.api,
  });

  @override
  State<MyFineSuggestionsPage> createState() => _MyFineSuggestionsPageState();
}

class _MyFineSuggestionsPageState extends State<MyFineSuggestionsPage> {
  bool _loading = true;
  bool _refreshing = false;

  List<FineSuggestionDto> _items = const [];
  Map<String, UserPickerDto> _userById = const {};
  Map<String, FineCatalogItemDto> _catalogById = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    if (mounted) {
      setState(() {
        _loading = !force && _items.isEmpty;
        _refreshing = force || _items.isNotEmpty;
      });
    }

    try {
      final results = await Future.wait([
        widget.api.listSuggestions(mine: true, status: 'PENDING'),
        widget.api.pickerUsers(),
        widget.api.listFineCatalog(active: null),
      ]);

      final items = (results[0] as List<FineSuggestionDto>).toList()
        ..sort((a, b) {
          final aPending = a.status.toUpperCase() == 'PENDING' ? 0 : 1;
          final bPending = b.status.toUpperCase() == 'PENDING' ? 0 : 1;
          final c0 = aPending.compareTo(bPending);
          if (c0 != 0) return c0;

          return b.createdAt.compareTo(a.createdAt);
        });

      final users = results[1] as List<UserPickerDto>;
      final catalog = results[2] as List<FineCatalogItemDto>;

      if (!mounted) return;
      setState(() {
        _items = items;
        _userById = {for (final u in users) u.id: u};
        _catalogById = {for (final c in catalog) c.id: c};
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Vorschläge laden fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
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

  Color _statusColor(BuildContext context, String status) {
    final cs = Theme.of(context).colorScheme;
    switch (status.toUpperCase()) {
      case 'PENDING':
        return cs.tertiaryContainer;
      case 'ACCEPTED':
        return cs.primaryContainer;
      case 'REJECTED':
        return cs.errorContainer;
      default:
        return cs.surfaceContainerHighest;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Vorschläge',
      showNotificationButton: false,
      showProfileButton: false,
      actions: [
        IconButton(
          tooltip: 'Neu laden',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loading ? null : () => _load(force: true),
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: () => _load(force: true),
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (_refreshing)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  final changed = await context.push<bool>('/suggestions/new');
                  if (changed == true && mounted) {
                    _load(force: true);
                  }
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('Neuen Vorschlag erstellen'),
              ),
            ),
            const SizedBox(height: 12),
            if (_items.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Icon(Icons.inbox_rounded, size: 40),
                      const SizedBox(height: 12),
                      Text(
                        'Noch keine Beihängungsvorschläge.',
                        style: Theme.of(context).textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Erstelle oben deinen ersten Vorschlag.',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              for (final s in _items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: ListTile(
                      titleAlignment: ListTileTitleAlignment.center,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      leading: const Icon(Icons.add_comment_rounded),
                      title: Text(_titleForSuggestion(s)),
                      subtitle: Text(
                        'Betrag: ${Format.centsToEur(s.amountCents ?? 0)}\n'
                            'Bbr.: ${s.targetUserIds.map(_userLabel).join(', ')}\n'
                            'Datum: ${Format.dateOnlyShort(s.fineDate)}',
                      ),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _statusColor(context, s.status),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              _statusLabel(s.status),
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right_rounded),
                        ],
                      ),
                      onTap: () async {
                        final changed = await context.push<bool>('/suggestions/${s.id}');
                        if (changed == true && mounted) {
                          _load(force: true);
                        }
                      },
                    )
                  ),
                ),
          ],
        ),
      ),
    );
  }
}