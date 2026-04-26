import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../api/api_client.dart';
import '../../../auth/auth_store.dart';
import '../../../auth/roles.dart';
import '../../../common/format.dart';
import '../../../common/widgets/app_scaffold.dart';
import '../../../models/dtos.dart';

class OfficeFineSuggestionsPage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;

  const OfficeFineSuggestionsPage({
    super.key,
    required this.api,
    required this.authStore,
  });

  @override
  State<OfficeFineSuggestionsPage> createState() =>
      _OfficeFineSuggestionsPageState();
}

class _OfficeFineSuggestionsPageState
    extends State<OfficeFineSuggestionsPage> {
  bool _loading = true;
  bool _acting = false;

  List<FineSuggestionDto> _items = const [];
  Map<String, UserPickerDto> _userById = const {};
  Map<String, FineCatalogItemDto> _catalogById = const {};

  static const String _statusOpen = 'PENDING';

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool _canDecide() {
    final roles = Roles.fromAccessToken(widget.authStore.accessToken);
    return roles.contains(AppRole.admin) ||
        roles.contains(AppRole.senior) ||
        roles.contains(AppRole.housekeeping);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final suggestions =
      await widget.api.listSuggestions(status: _statusOpen);
      final users = await widget.api.pickerUsers();
      final catalog = await widget.api.listFineCatalog(active: null);

      if (!mounted) return;
      setState(() {
        _items = suggestions;
        _userById = {for (final u in users) u.id: u};
        _catalogById = {for (final c in catalog) c.id: c};
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

  String _titleForSuggestion(FineSuggestionDto s) {
    if (s.type == FineType.catalog && s.catalogItemId != null) {
      final item = _catalogById[s.catalogItemId!];
      final t = item?.title.trim() ?? '';
      if (t.isNotEmpty) return t;
      return 'Katalog-Beihängung';
    }

    final r = (s.reason ?? '').trim();
    if (r.isNotEmpty) return r;

    return 'Beihängungsvorschlag';
  }

  Future<void> _accept(FineSuggestionDto s) async {
    if (!_canDecide()) return;

    setState(() => _acting = true);
    try {
      final res = await widget.api.acceptSuggestion(s.id);

      if (!mounted) return;

      final fineId = res.fineId ?? res.fine?.id;
      if (fineId != null && fineId.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vorschlag akzeptiert.')),
        );
        context.push('/fines/$fineId');
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vorschlag akzeptiert (Fine-ID fehlt).'),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Akzeptieren fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _reject(FineSuggestionDto s) async {
    if (!_canDecide()) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vorschlag ablehnen?'),
        content: const Text('Der Vorschlag wird als abgelehnt markiert.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Ablehnen'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _acting = true);
    try {
      await widget.api.rejectSuggestion(s.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vorschlag abgelehnt.')),
      );

      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ablehnen fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canDecide = _canDecide();

    return AppScaffold(
      title: 'Vorschläge',
      showNotificationButton: false,
      showProfileButton: false,
      actions: [
        IconButton(
          tooltip: 'Neu laden',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: (_loading || _acting) ? null : _load,
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _load,
        child: _items.isEmpty
            ? ListView(
          children: const [
            SizedBox(height: 64),
            Center(child: Text('Keine offenen Vorschläge.')),
          ],
        )
            : ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: _items.length,
          itemBuilder: (ctx, i) {
            final s = _items[i];

            final title = _titleForSuggestion(s);
            final amount =
            Format.centsToEur(s.amountCents ?? 0);
            final creator =
            _userLabel(s.creatorUserId);
            final targets =
            s.targetUserIds.map(_userLabel).join(', ');
            final reason =
            (s.reason ?? '').trim();

            final showReason = reason.isNotEmpty &&
                (s.type == FineType.catalog ||
                    title.trim() != reason);

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium,
                          ),
                        ),
                        if (_acting)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child:
                            CircularProgressIndicator(
                                strokeWidth: 2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Betrag: $amount'),
                    const SizedBox(height: 6),
                    Text(
                        'Datum: ${Format.dateOnlyShort(s.fineDate)}'),
                    const SizedBox(height: 6),
                    if (showReason) ...[
                      Text(
                        s.type == FineType.catalog
                            ? 'Hinweis: $reason'
                            : 'Grund: $reason',
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text('Bbr.: $targets'),
                    const SizedBox(height: 6),
                    Text('Vorschlag von: $creator'),
                    const SizedBox(height: 6),
                    Text('Status: ${s.status}'),
                    const SizedBox(height: 6),
                    Text(
                        'Erstellt: ${Format.dateTimeShort(s.createdAt)}'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: (!canDecide ||
                                _acting)
                                ? null
                                : () => _accept(s),
                            child:
                            const Text('Akzeptieren'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.tonal(
                            onPressed: (!canDecide ||
                                _acting)
                                ? null
                                : () => _reject(s),
                            child:
                            const Text('Ablehnen'),
                          ),
                        ),
                      ],
                    ),
                    if (!canDecide)
                      Padding(
                        padding:
                        const EdgeInsets.only(top: 10),
                        child: Text(
                          'Du hast keine Rechte zum Akzeptieren/Ablehnen.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
