import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../api/api_client.dart';
import '../../../auth/auth_store.dart';
import '../../../auth/roles.dart';
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
  final _defaultCentsCtrl = TextEditingController();
  bool _active = true;

  bool get _isEdit => widget.itemId != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _defaultCentsCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final roles = Roles.fromAccessToken(widget.authStore.accessToken);
      if (!Roles.canManageCatalog(roles)) {
        if (!mounted) return;
        context.pop();
        return;
      }

      if (_isEdit) {
        final it = await widget.api.getFineCatalogItem(widget.itemId!);
        _titleCtrl.text = it.title;
        _defaultCentsCtrl.text = (it.defaultAmountCents ?? 0).toString();
        _active = it.active;
      } else {
        _active = true;
        _defaultCentsCtrl.text = '0';
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

  int _parseCents(String s) => int.tryParse(s.trim()) ?? 0;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      if (_isEdit) {
        await widget.api.updateFineCatalogItem(
          widget.itemId!,
          UpdateFineCatalogItemRequest(
            title: _titleCtrl.text.trim(),
            defaultAmountCents: _parseCents(_defaultCentsCtrl.text),
            active: _active,
          ),
        );
      } else {
        await widget.api.createFineCatalogItem(
          CreateFineCatalogItemRequest(
            title: _titleCtrl.text.trim(),
            defaultAmountCents: _parseCents(_defaultCentsCtrl.text),
            active: _active,
          ),
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gespeichert.')));
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Speichern fehlgeschlagen: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete() async {
    if (!_isEdit) return;

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
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Löschen fehlgeschlagen: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roles = Roles.fromAccessToken(widget.authStore.accessToken);
    final can = Roles.canManageCatalog(roles);

    return AppScaffold(
      title: _isEdit ? 'Katalogeintrag bearbeiten' : 'Katalogeintrag anlegen',
      actions: [
        if (can && _isEdit)
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
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    TextFormField(
                      controller: _titleCtrl,
                      decoration: const InputDecoration(labelText: 'Titel'),
                      validator: (v) => ((v ?? '').trim().isEmpty) ? 'Pflichtfeld' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _defaultCentsCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Default Betrag (Cent)',
                        hintText: 'z.B. 150',
                      ),
                      validator: (v) {
                        final s = (v ?? '').trim();
                        if (s.isEmpty) return 'Pflichtfeld';
                        if (int.tryParse(s) == null) return 'Zahl erwartet';
                        if ((int.tryParse(s) ?? 0) < 0) return '>= 0';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Aktiv'),
                      value: _active,
                      onChanged: (v) => setState(() => _active = v),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _save,
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
