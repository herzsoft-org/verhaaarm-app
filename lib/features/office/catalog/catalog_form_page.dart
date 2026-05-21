import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../api/api_client.dart';
import '../../../auth/auth_store.dart';
import '../../../auth/roles.dart';
import '../../../common/format.dart';
import '../../../common/widgets/app_scaffold.dart';
import '../../../models/dtos.dart';

class CatalogFormPage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;
  final String? itemId;

  const CatalogFormPage({super.key, required this.api, required this.authStore, this.itemId});

  @override
  State<CatalogFormPage> createState() => _CatalogFormPageState();
}

class _CatalogFormPageState extends State<CatalogFormPage> {
  final _formKey = GlobalKey<FormState>();

  bool _loading = true;

  final _titleCtrl = TextEditingController();
  final _defaultEurCtrl = TextEditingController();
  bool _active = true;

  bool _isSystemAttendanceItem = false;

  bool get _isEdit => widget.itemId != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _defaultEurCtrl.dispose();
    super.dispose();
  }

  String _toEurText(int cents) {
    final s = Format.centsToEur(cents);
    return s.replaceAll('€', '').trim();
  }

  int? _parseOptionalEurToCents(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    return Format.eurTextToCents(t);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final roles = widget.authStore.currentRoles;
      if (!Roles.canManageCatalog(roles)) {
        if (!mounted) return;
        context.pop();
        return;
      }

      // Get system IDs from backend config (source of truth)
      final cfg = await widget.api.getAttendanceFineConfig();
      final sys = <String>{
        if ((cfg.lateCatalogItemId ?? '').trim().isNotEmpty) cfg.lateCatalogItemId!.trim(),
        if ((cfg.absentCatalogItemId ?? '').trim().isNotEmpty) cfg.absentCatalogItemId!.trim(),
      };

      if (_isEdit) {
        final it = await widget.api.getFineCatalogItem(widget.itemId!);

        _isSystemAttendanceItem = sys.contains(it.id);

        _titleCtrl.text = it.title;
        _defaultEurCtrl.text = it.defaultAmountCents == null ? '' : _toEurText(it.defaultAmountCents!);
        _active = it.active;
      } else {
        _isSystemAttendanceItem = false;
        _active = true;
        _titleCtrl.text = '';
        _defaultEurCtrl.text = '';
      }

      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Laden fehlgeschlagen: $e')));
      context.pop();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final cents = _parseOptionalEurToCents(_defaultEurCtrl.text);

      if (_isEdit) {
        if (_isSystemAttendanceItem) {
          await widget.api.updateFineCatalogItem(
            widget.itemId!,
            UpdateFineCatalogItemRequest(
              // System: only amount
              title: null,
              defaultAmountCents: cents,
              active: null,
            ),
          );
        } else {
          await widget.api.updateFineCatalogItem(
            widget.itemId!,
            UpdateFineCatalogItemRequest(
              title: _titleCtrl.text.trim(),
              defaultAmountCents: cents,
              active: _active,
            ),
          );
        }
      } else {
        await widget.api.createFineCatalogItem(
          CreateFineCatalogItemRequest(
            title: _titleCtrl.text.trim(),
            defaultAmountCents: cents,
            active: _active,
          ),
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gespeichert.')));
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Speichern fehlgeschlagen: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete() async {
    if (!_isEdit) return;

    // Hard guard against backend 500
    if (_isSystemAttendanceItem) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Systemeinträge können nicht gelöscht werden.')),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Löschen?'),
        content: const Text('Katalogeintrag wirklich löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Löschen')),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _loading = true);
    try {
      await widget.api.deleteFineCatalogItem(widget.itemId!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gelöscht.')));
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Löschen fehlgeschlagen: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roles = widget.authStore.currentRoles;
    final can = Roles.canManageCatalog(roles);

    return AppScaffold(
      title: _isEdit ? 'Katalogeintrag bearbeiten' : 'Katalogeintrag anlegen',
      actions: [
        if (can && _isEdit && !_isSystemAttendanceItem)
          IconButton(
            tooltip: 'Löschen',
            icon: const Icon(Icons.delete_rounded),
            onPressed: _loading ? null : _delete,
          ),
        IconButton(
          tooltip: 'Speichern',
          icon: const Icon(Icons.save_rounded),
          onPressed: _loading ? null : _save,
        ),
      ],
      body: !can
          ? const Center(child: Text('Keine Berechtigung.'))
          : _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (_isSystemAttendanceItem)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.lock_rounded),
                  title: Text('Systemeintrag (Anwesenheit)'),
                  subtitle: Text('Wird automatisch vergeben. Titel/Aktiv-Status sind gesperrt. '
                      'Du kannst nur den Default Betrag ändern.'),
                ),
              ),
            if (_isSystemAttendanceItem) const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    TextFormField(
                      controller: _titleCtrl,
                      enabled: !_isSystemAttendanceItem,
                      decoration: InputDecoration(
                        labelText: 'Titel',
                        helperText: _isSystemAttendanceItem ? 'Titel ist gesperrt (Systemeintrag).' : null,
                      ),
                      validator: (v) {
                        if (_isSystemAttendanceItem) return null;
                        return ((v ?? '').trim().isEmpty) ? 'Pflichtfeld' : null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _defaultEurCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Default Betrag (EUR)',
                        hintText: 'z.B. 2,50',
                      ),
                      validator: (v) {
                        final s = (v ?? '').trim();
                        if (s.isEmpty) return null;
                        final cents = Format.eurTextToCents(s);
                        if (cents == null) return 'Bitte gültigen Betrag angeben';
                        if (cents < 0) return '>= 0';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Aktiv'),
                      value: _active,
                      onChanged: _isSystemAttendanceItem ? null : (v) => setState(() => _active = v),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _loading ? null : _save,
                icon: const Icon(Icons.save_rounded),
                label: const Text('Speichern'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
