import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
import '../../auth/roles.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../common/widgets/busy_icon_button.dart';
import '../../models/dtos.dart';
import 'star_rating_widget.dart';

class SlushyRecipesPage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;

  const SlushyRecipesPage({super.key, required this.api, required this.authStore});

  @override
  State<SlushyRecipesPage> createState() => _SlushyRecipesPageState();
}

enum _SortMode { rating, newest }

class _SlushyRecipesPageState extends State<SlushyRecipesPage> {
  bool _loading = true;
  bool _refreshing = false;

  List<SlushyRecipeDto> _recipes = const [];
  _SortMode _sortMode = _SortMode.rating;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _sortRecipes(List<SlushyRecipeDto> recipes) {
    switch (_sortMode) {
      case _SortMode.rating:
        recipes.sort((a, b) {
          final c = b.ratingSummary.average.compareTo(a.ratingSummary.average);
          if (c != 0) return c;
          return b.ratingSummary.count.compareTo(a.ratingSummary.count);
        });
        break;
      case _SortMode.newest:
        recipes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
    }
  }

  void _setSortMode(_SortMode mode) {
    if (_sortMode == mode) return;
    setState(() {
      _sortMode = mode;
      final list = _recipes.toList(growable: true);
      _sortRecipes(list);
      _recipes = List<SlushyRecipeDto>.unmodifiable(list);
    });
  }

  Future<void> _load({bool force = false}) async {
    if (mounted) {
      setState(() {
        if (_recipes.isEmpty) {
          _loading = true;
        } else {
          _refreshing = true;
        }
      });
    }

    try {
      final recipes = await widget.api.listSlushyRecipes();
      _sortRecipes(recipes);

      if (!mounted) return;
      setState(() => _recipes = List<SlushyRecipeDto>.unmodifiable(recipes));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rezepte laden fehlgeschlagen: $e')),
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

  bool _canManage(SlushyRecipeDto r) {
    final roles = widget.authStore.currentRoles;
    if (Roles.canManageSlushyRecipes(roles)) return true;
    final myId = widget.authStore.currentUser?.id;
    return myId != null && myId == r.createdByUserId;
  }

  Future<void> _openRecipe(SlushyRecipeDto r) async {
    final changed = await context.push<bool>('/slushy-recipes/${r.id}', extra: r);
    if (changed == true && mounted) {
      await _load(force: true);
    }
  }

  Future<void> _create() async {
    final created = await context.push<SlushyRecipeDto>('/slushy-recipes/new');
    if (created != null && mounted) {
      await _load(force: true);
    }
  }

  Future<void> _edit(SlushyRecipeDto r) async {
    final changed = await context.push<SlushyRecipeDto>('/slushy-recipes/${r.id}/edit', extra: r);
    if (changed != null && mounted) {
      await _load(force: true);
    }
  }

  Future<void> _delete(SlushyRecipeDto r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rezept löschen'),
        content: Text('„${r.title}“ löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await widget.api.deleteSlushyRecipe(r.id);
      if (!mounted) return;
      setState(() => _recipes = List<SlushyRecipeDto>.unmodifiable(_recipes.where((x) => x.id != r.id)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Löschen fehlgeschlagen: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Slushy Rezepte',
      showNotificationButton: false,
      showProfileButton: false,
      actions: [
        PopupMenuButton<_SortMode>(
          tooltip: 'Sortieren',
          icon: const Icon(Icons.sort_rounded),
          onSelected: _setSortMode,
          itemBuilder: (ctx) => [
            CheckedPopupMenuItem(
              value: _SortMode.rating,
              checked: _sortMode == _SortMode.rating,
              child: const Text('Nach Bewertung'),
            ),
            CheckedPopupMenuItem(
              value: _SortMode.newest,
              checked: _sortMode == _SortMode.newest,
              child: const Text('Neueste zuerst'),
            ),
          ],
        ),
        BusyIconButton(
          busy: _loading || _refreshing,
          tooltip: 'Neu laden',
          icon: Icons.refresh_rounded,
          onPressed: () => _load(force: true),
        ),
        IconButton(
          tooltip: 'Neu',
          icon: const Icon(Icons.add_rounded),
          onPressed: _create,
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _load(force: true),
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  if (_recipes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('Noch keine Slushy Rezepte.')),
                    )
                  else
                    ..._recipes.map(
                      (r) => _SlushyRecipeCard(
                        recipe: r,
                        canManage: _canManage(r),
                        onTap: () => _openRecipe(r),
                        onEdit: () => _edit(r),
                        onDelete: () => _delete(r),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _SlushyRecipeCard extends StatelessWidget {
  final SlushyRecipeDto recipe;
  final bool canManage;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SlushyRecipeCard({
    required this.recipe,
    required this.canManage,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(recipe.title, style: theme.textTheme.titleMedium),
                  ),
                  if (canManage)
                    PopupMenuButton<_RecipeMenuAction>(
                      tooltip: 'Aktionen',
                      onSelected: (a) {
                        switch (a) {
                          case _RecipeMenuAction.edit:
                            onEdit();
                            break;
                          case _RecipeMenuAction.delete:
                            onDelete();
                            break;
                        }
                      },
                      itemBuilder: (ctx) => const [
                        PopupMenuItem(
                          value: _RecipeMenuAction.edit,
                          child: Row(
                            children: [
                              Icon(Icons.edit_rounded),
                              SizedBox(width: 10),
                              Text('Bearbeiten'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: _RecipeMenuAction.delete,
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline_rounded),
                              SizedBox(width: 10),
                              Text('Löschen'),
                            ],
                          ),
                        ),
                      ],
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.more_vert_rounded),
                      ),
                    ),
                ],
              ),
              if ((recipe.description ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  recipe.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 8),
              StarRatingDisplay(
                average: recipe.ratingSummary.average,
                count: recipe.ratingSummary.count,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _RecipeMenuAction { edit, delete }
