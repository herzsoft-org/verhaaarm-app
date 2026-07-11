import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
import '../../auth/roles.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../models/dtos.dart';

class SlushyRecipeFormPage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;
  final String? recipeId;
  final SlushyRecipeDto? initial;

  const SlushyRecipeFormPage({
    super.key,
    required this.api,
    required this.authStore,
    this.recipeId,
    this.initial,
  });

  @override
  State<SlushyRecipeFormPage> createState() => _SlushyRecipeFormPageState();
}

class _IngredientRow {
  final TextEditingController name;
  final TextEditingController amount;

  _IngredientRow({String name = '', String amount = ''})
      : name = TextEditingController(text: name),
        amount = TextEditingController(text: amount);

  void dispose() {
    name.dispose();
    amount.dispose();
  }
}

class _SlushyRecipeFormPageState extends State<SlushyRecipeFormPage> {
  final _formKey = GlobalKey<FormState>();

  final _titleCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final List<_IngredientRow> _ingredientRows = [];

  bool _loading = false;
  bool _saving = false;

  bool get _isEdit => widget.recipeId != null;

  bool get _canManage {
    final initial = widget.initial;
    if (initial == null) return true;
    final roles = widget.authStore.currentRoles;
    if (Roles.canManageSlushyRecipes(roles)) return true;
    final myId = widget.authStore.currentUser?.id;
    return myId != null && myId == initial.createdByUserId;
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _titleCtrl.text = initial.title;
      _descriptionCtrl.text = initial.description ?? '';
      for (final ing in initial.ingredients) {
        _ingredientRows.add(_IngredientRow(name: ing.name, amount: ing.amount ?? ''));
      }
    }
    if (_ingredientRows.isEmpty) {
      _ingredientRows.add(_IngredientRow());
    }

    if (_isEdit && initial == null) {
      _load();
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descriptionCtrl.dispose();
    for (final row in _ingredientRows) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final recipe = await widget.api.getSlushyRecipe(widget.recipeId!);
      if (!mounted) return;
      setState(() {
        _titleCtrl.text = recipe.title;
        _descriptionCtrl.text = recipe.description ?? '';
        for (final row in _ingredientRows) {
          row.dispose();
        }
        _ingredientRows
          ..clear()
          ..addAll(recipe.ingredients.map(
            (ing) => _IngredientRow(name: ing.name, amount: ing.amount ?? ''),
          ));
        if (_ingredientRows.isEmpty) _ingredientRows.add(_IngredientRow());
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Laden fehlgeschlagen: $e')));
      context.pop();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _addIngredientRow() {
    setState(() => _ingredientRows.add(_IngredientRow()));
  }

  void _removeIngredientRow(int index) {
    setState(() {
      _ingredientRows.removeAt(index).dispose();
      if (_ingredientRows.isEmpty) _ingredientRows.add(_IngredientRow());
    });
  }

  List<SlushyIngredientDto> _collectIngredients() {
    return _ingredientRows
        .where((row) => row.name.text.trim().isNotEmpty)
        .map((row) => SlushyIngredientDto(
              name: row.name.text.trim(),
              amount: row.amount.text.trim().isEmpty ? null : row.amount.text.trim(),
            ))
        .toList(growable: false);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final title = _titleCtrl.text.trim();
      final description = _descriptionCtrl.text.trim();
      final ingredients = _collectIngredients();

      final SlushyRecipeDto saved;
      if (_isEdit) {
        saved = await widget.api.updateSlushyRecipe(
          widget.recipeId!,
          UpdateSlushyRecipeRequest(
            title: title,
            description: description,
            ingredients: ingredients,
          ),
        );
      } else {
        saved = await widget.api.createSlushyRecipe(
          CreateSlushyRecipeRequest(
            title: title,
            description: description.isEmpty ? null : description,
            ingredients: ingredients,
          ),
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gespeichert.')));
      context.pop(saved);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Speichern fehlgeschlagen: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    if (!_isEdit) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rezept löschen'),
        content: Text('„${_titleCtrl.text.trim()}“ wirklich löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen')),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _saving = true);
    try {
      await widget.api.deleteSlushyRecipe(widget.recipeId!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gelöscht.')));
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Löschen fehlgeschlagen: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _loading || _saving;

    return AppScaffold(
      title: _isEdit ? 'Rezept bearbeiten' : 'Rezept anlegen',
      showNotificationButton: false,
      showProfileButton: false,
      actions: [
        if (_isEdit && _canManage)
          IconButton(
            tooltip: 'Löschen',
            icon: const Icon(Icons.delete_rounded),
            onPressed: busy ? null : _delete,
          ),
        IconButton(
          tooltip: 'Speichern',
          icon: const Icon(Icons.save_rounded),
          onPressed: busy ? null : _save,
        ),
      ],
      body: !_canManage
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
                                controller: _descriptionCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Kurzbeschreibung',
                                ),
                                maxLines: 3,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text('Zutaten', style: Theme.of(context).textTheme.titleSmall),
                                  const Spacer(),
                                  TextButton.icon(
                                    onPressed: _addIngredientRow,
                                    icon: const Icon(Icons.add_rounded),
                                    label: const Text('Zutat'),
                                  ),
                                ],
                              ),
                              for (var i = 0; i < _ingredientRows.length; i++)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: TextFormField(
                                          controller: _ingredientRows[i].name,
                                          decoration: const InputDecoration(labelText: 'Zutat'),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        flex: 2,
                                        child: TextFormField(
                                          controller: _ingredientRows[i].amount,
                                          decoration: const InputDecoration(
                                            labelText: 'Menge',
                                            hintText: 'optional',
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Entfernen',
                                        icon: const Icon(Icons.remove_circle_outline_rounded),
                                        onPressed: () => _removeIngredientRow(i),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: busy ? null : _save,
                          icon: const Icon(Icons.save_rounded),
                          label: Text(_isEdit ? 'Speichern' : 'Erstellen'),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
