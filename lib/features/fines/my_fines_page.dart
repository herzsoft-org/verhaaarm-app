import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../common/cache/app_cache.dart';
import '../../common/format.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../models/dtos.dart';

class MyFinesPage extends StatefulWidget {
  final ApiClient api;

  const MyFinesPage({super.key, required this.api});

  @override
  State<MyFinesPage> createState() => _MyFinesPageState();
}

class _MyFinesPageState extends State<MyFinesPage> {
  static const _ttlMyFines = Duration(minutes: 3);

  static const _kMyFinesActivePeriod = 'myfines.activePeriod';
  static const _kMyFinesBalance = 'myfines.balance';
  static const _kMyFinesFines = 'myfines.fines';
  static const _kMyFinesUsers = 'myfines.users';
  static const _kMyFinesCatalog = 'myfines.catalog';

  bool _loading = true;
  bool _refreshing = false;

  ConventPeriodDto? _activePeriod;
  UserBalanceDto? _balance;

  List<FineDto> _currentPeriodFines = const [];

  Map<String, UserPickerDto> _userById = const {};
  Map<String, FineCatalogItemDto> _catalogById = const {};

  bool _isNoActivePeriodError(Object e) {
    if (e is DioException) {
      final code = e.response?.statusCode;
      return code == 404;
    }
    return false;
  }

  Map<String, dynamic> _encodePeriod(ConventPeriodDto p) => {
    'id': p.id,
    'semester': p.semester,
    'startAt': p.startAt,
    'endAt': p.endAt,
    'active': p.active,
    'locked': p.locked,
  };

  ConventPeriodDto _decodePeriod(Object json) =>
      ConventPeriodDto.fromJson((json as Map).cast<String, dynamic>());

  Map<String, dynamic> _encodeBalance(UserBalanceDto b) => {
    'userId': b.userId,
    'id': b.userId, // legacy callers
    'balanceCents': b.balanceCents,
    'balanceFormatted': b.balanceFormatted,
  };

  UserBalanceDto _decodeBalance(Object json) => UserBalanceDto.fromJson((json as Map).cast<String, dynamic>());

  Map<String, dynamic> _encodeUser(UserPickerDto u) => {
    'id': u.id,
    'username': u.username,
    'displayName': u.displayName,
  };

  UserPickerDto _decodeUser(Object json) => UserPickerDto.fromJson((json as Map).cast<String, dynamic>());

  Map<String, dynamic> _encodeFine(FineDto f) => {
    'id': f.id,
    'creatorUserId': f.creatorUserId,
    'targetUserIds': f.targetUserIds,
    'amountCents': f.amountCents,
    'reason': f.reason,
    'catalogItemId': f.catalogItemId,
    'fineDate': f.fineDate,
    'createdAt': f.createdAt,
    'type': f.type.name,
    'suggesterUserId': f.suggesterUserId,
    'acceptedFromSuggestionId': f.acceptedFromSuggestionId,
  };

  FineDto _decodeFine(Object json) => FineDto.fromJson((json as Map).cast<String, dynamic>());

  Map<String, dynamic> _encodeCatalogItem(FineCatalogItemDto c) => {
    'id': c.id,
    'title': c.title,
    'active': c.active,
    'defaultAmountCents': c.defaultAmountCents,
  };

  FineCatalogItemDto _decodeCatalogItem(Object json) =>
      FineCatalogItemDto.fromJson((json as Map).cast<String, dynamic>());

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _userLabel(String id) => _userById[id]?.displayName ?? id;

  String _fineTitle(FineDto f) {
    if (f.type == FineType.catalog && f.catalogItemId != null) {
      final item = _catalogById[f.catalogItemId!];
      if (item != null && item.title.trim().isNotEmpty) return item.title.trim();
    }
    final r = (f.reason ?? '').trim();
    if (r.isNotEmpty) return r;
    return 'Beihängung';
  }

  bool _isFineInActivePeriod(FineDto f, ConventPeriodDto p) {
    // backend semantics: [startAt, endAt) (end exclusive)
    final d = _parseLocalDateOnly(f.fineDate); // local date at midnight
    final start = p.startDateLocal;
    final end = p.endDateLocal; // NOTE: endAt is exclusive semantically
    return !d.isBefore(start) && d.isBefore(end);
  }

  Future<void> _load({bool force = false}) async {
    try {
      final cPeriod = await AppCache.I.entryOrLoadPersisted<ConventPeriodDto>(
        _kMyFinesActivePeriod,
        decode: _decodePeriod,
      );
      final cBal = await AppCache.I.entryOrLoadPersisted<UserBalanceDto>(
        _kMyFinesBalance,
        decode: _decodeBalance,
      );
      final cFines = await AppCache.I.entryOrLoadPersisted<List<FineDto>>(
        _kMyFinesFines,
        decode: (json) => (json as List).map((e) => _decodeFine(e as Object)).toList(growable: false),
      );
      final cUsers = await AppCache.I.entryOrLoadPersisted<List<UserPickerDto>>(
        _kMyFinesUsers,
        decode: (json) => (json as List).map((e) => _decodeUser(e as Object)).toList(growable: false),
      );
      final cCatalog = await AppCache.I.entryOrLoadPersisted<List<FineCatalogItemDto>>(
        _kMyFinesCatalog,
        decode: (json) => (json as List).map((e) => _decodeCatalogItem(e as Object)).toList(growable: false),
      );

      final hasAnyCache = (cPeriod != null) || (cBal != null) || (cFines != null) || (cUsers != null) || (cCatalog != null);

      if (hasAnyCache && mounted) {
        final users = List<UserPickerDto>.from(cUsers?.value ?? const <UserPickerDto>[]);
        final catalog = List<FineCatalogItemDto>.from(cCatalog?.value ?? const <FineCatalogItemDto>[]);

        final userById = {for (final u in users) u.id: u};
        final catalogById = {for (final c in catalog) c.id: c};

        final period = cPeriod?.value;
        final allFines = cFines?.value ?? const <FineDto>[];

        final filtered = (period == null)
            ? const <FineDto>[]
            : allFines.where((f) => _isFineInActivePeriod(f, period)).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        setState(() {
          _activePeriod = period;
          _balance = cBal?.value;
          _currentPeriodFines = filtered;
          _userById = userById;
          _catalogById = catalogById;
          _loading = false;
        });
      }

      final cacheFresh = (cFines != null && cFines.isFresh(_ttlMyFines)) &&
          (cUsers != null && cUsers.isFresh(_ttlMyFines)) &&
          (cCatalog != null && cCatalog.isFresh(_ttlMyFines)) &&
          // period/balance are also cached, but can be absent (no active period). Treat absence as OK.
          true;

      if (!force && cacheFresh) return;

      final showFullSpinner = !hasAnyCache;
      if (mounted) {
        setState(() {
          _loading = showFullSpinner;
          _refreshing = !showFullSpinner;
        });
      }

      try {
        // Active period can be 404 (no active period)
        ConventPeriodDto? period;
        try {
          period = await widget.api.getActivePeriod();
        } catch (e) {
          if (_isNoActivePeriodError(e)) {
            period = null;
          } else {
            rethrow;
          }
        }

        // Balance can be 404 too (same reason); keep nullable
        UserBalanceDto? bal;
        try {
          bal = await widget.api.getMyBalance();
        } catch (e) {
          if (_isNoActivePeriodError(e)) {
            bal = null;
          } else {
            rethrow;
          }
        }

        final fines = await widget.api.listFines(); // visible fines (member: already "mine")
        final users = await widget.api.pickerUsers();
        final catalog = await widget.api.listFineCatalog(active: null);

        await AppCache.I.setPersisted<List<FineDto>>(
          _kMyFinesFines,
          List<FineDto>.unmodifiable(fines),
          encode: (v) => v.map(_encodeFine).toList(growable: false),
        );
        await AppCache.I.setPersisted<List<UserPickerDto>>(
          _kMyFinesUsers,
          List<UserPickerDto>.unmodifiable(users),
          encode: (v) => v.map(_encodeUser).toList(growable: false),
        );
        await AppCache.I.setPersisted<List<FineCatalogItemDto>>(
          _kMyFinesCatalog,
          List<FineCatalogItemDto>.unmodifiable(catalog),
          encode: (v) => v.map(_encodeCatalogItem).toList(growable: false),
        );

        if (period != null) {
          await AppCache.I.setPersisted<ConventPeriodDto>(
            _kMyFinesActivePeriod,
            period,
            encode: _encodePeriod,
          );
        } else {
          await AppCache.I.removePersisted(_kMyFinesActivePeriod);
        }

        if (bal != null) {
          await AppCache.I.setPersisted<UserBalanceDto>(
            _kMyFinesBalance,
            bal,
            encode: _encodeBalance,
          );
        } else {
          await AppCache.I.removePersisted(_kMyFinesBalance);
        }

        final userById = {for (final u in users) u.id: u};
        final catalogById = {for (final c in catalog) c.id: c};

        final filtered = (period == null)
            ? const <FineDto>[]
            : fines.where((f) => _isFineInActivePeriod(f, period!)).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        if (!mounted) return;
        setState(() {
          _activePeriod = period;
          _balance = bal;
          _currentPeriodFines = filtered;
          _userById = userById;
          _catalogById = catalogById;
        });
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Beihängungen laden fehlgeschlagen: $e')),
        );
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

  @override
  Widget build(BuildContext context) {
    final p = _activePeriod;
    final balanceText = (_balance?.balanceFormatted ?? '').trim();

    return AppScaffold(
      title: 'Meine Beihängungen',
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

            // Header card: active period + balance (if available)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Aktuelle Conventsperiode', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(
                      p == null
                          ? 'Keine aktive Conventsperiode'
                          : '${p.semester} · ${Format.dateOnlyShort(p.startAt)} – ${Format.dateOnlyShort(p.endAt)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 10),
                    Text('Saldo', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(
                      balanceText.isNotEmpty ? balanceText : (p == null ? '—' : '…'),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            if (p == null)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Keine Beihängungen: Es gibt aktuell keine aktive Conventsperiode.'),
              )
            else if (_currentPeriodFines.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Keine Beihängungen in der aktuellen Conventsperiode gefunden.'),
              )
            else
              for (final f in _currentPeriodFines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    elevation: 0,
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: ListTile(
                      titleAlignment: ListTileTitleAlignment.center,
                      leading: const Icon(Icons.gavel_rounded),
                      title: Text(_fineTitle(f)),
                      subtitle: Text(_subtitleForFine(f)),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.push('/fines/${f.id}'),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  DateTime _parseLocalDateOnly(String s) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s.trim());
    if (m == null) return DateTime.fromMillisecondsSinceEpoch(0);
    final y = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final d = int.parse(m.group(3)!);
    return DateTime(y, mo, d); // local midnight
  }


  String _subtitleForFine(FineDto f) {
    final amount = f.amountCents ?? 0;

    final creator = (f.creatorUserId ?? '').toString();
    final creatorLabel = creator.isEmpty ? '' : _userLabel(creator);

    return 'Betrag: ${Format.centsToEur(amount)}\n'
        'Beihängungsdatum: ${Format.dateOnlyShort(f.fineDate)}'
        '${creator.isEmpty ? '' : '\nErstellt von: $creatorLabel'}';
  }
}
