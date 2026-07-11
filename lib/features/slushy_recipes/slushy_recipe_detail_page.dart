import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
import '../../auth/roles.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../models/dtos.dart';
import 'star_rating_widget.dart';

class SlushyRecipeDetailPage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;
  final String recipeId;
  final SlushyRecipeDto? initialRecipe;

  const SlushyRecipeDetailPage({
    super.key,
    required this.api,
    required this.authStore,
    required this.recipeId,
    this.initialRecipe,
  });

  @override
  State<SlushyRecipeDetailPage> createState() => _SlushyRecipeDetailPageState();
}

class _SlushyRecipeDetailPageState extends State<SlushyRecipeDetailPage> {
  SlushyRecipeDto? _recipe;
  bool _loading = true;
  bool _rating = false;
  bool _dirty = false;
  bool _showRatingInput = false;

  int _myStars = 0;
  final _commentCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _recipe = widget.initialRecipe;
    _loading = widget.initialRecipe == null;
    _applyMyRating(widget.initialRecipe);
    _load();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  void _applyMyRating(SlushyRecipeDto? recipe) {
    _myStars = recipe?.ratingSummary.myStars ?? 0;
    _commentCtrl.text = recipe?.ratingSummary.myComment ?? '';
  }

  bool get _hasMyRating => _recipe?.ratingSummary.myStars != null;

  Future<void> _load() async {
    try {
      final recipe = await widget.api.getSlushyRecipe(widget.recipeId);
      if (!mounted) return;
      setState(() {
        _recipe = recipe;
        _loading = false;
        _applyMyRating(recipe);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rezept laden fehlgeschlagen: $e')),
      );
    }
  }

  bool get _canManage {
    final recipe = _recipe;
    if (recipe == null) return false;
    final roles = widget.authStore.currentRoles;
    if (Roles.canManageSlushyRecipes(roles)) return true;
    final myId = widget.authStore.currentUser?.id;
    return myId != null && myId == recipe.createdByUserId;
  }

  Future<void> _submitRating() async {
    if (_myStars < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte mindestens 1 Stern vergeben.')),
      );
      return;
    }

    setState(() => _rating = true);
    try {
      final comment = _commentCtrl.text.trim();
      final updated = await widget.api.rateSlushyRecipe(
        widget.recipeId,
        RateSlushyRecipeRequest(stars: _myStars, comment: comment.isEmpty ? null : comment),
      );
      if (!mounted) return;
      setState(() {
        _recipe = updated;
        _dirty = true;
        _showRatingInput = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bewertung gespeichert.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bewertung fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _rating = false);
    }
  }

  Future<void> _deleteRating() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bewertung löschen'),
        content: const Text('Deine Bewertung wirklich löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen')),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _rating = true);
    try {
      final updated = await widget.api.deleteSlushyRecipeRating(widget.recipeId);
      if (!mounted) return;
      setState(() {
        _recipe = updated;
        _dirty = true;
        _showRatingInput = false;
        _applyMyRating(updated);
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bewertung gelöscht.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Löschen fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _rating = false);
    }
  }

  Future<void> _edit() async {
    final recipe = _recipe;
    if (recipe == null) return;

    final changed = await context.push<SlushyRecipeDto>(
      '/slushy-recipes/${recipe.id}/edit',
      extra: recipe,
    );

    if (changed != null && mounted) {
      setState(() {
        _recipe = changed;
        _dirty = true;
        _applyMyRating(changed);
      });
    }
  }

  Future<void> _delete() async {
    final recipe = _recipe;
    if (recipe == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rezept löschen'),
        content: Text('„${recipe.title}“ wirklich löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await widget.api.deleteSlushyRecipe(recipe.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gelöscht.')));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Löschen fehlgeschlagen: $e')),
      );
    }
  }

  String _formatDate(DateTime dt) {
    final d = dt.toLocal();
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final recipe = _recipe;
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop(result ?? _dirty);
      },
      child: AppScaffold(
        title: 'Slushy Rezept',
        showNotificationButton: false,
        showProfileButton: false,
        actions: [
          IconButton(
            tooltip: 'Neu laden',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
          ),
          if (recipe != null && _canManage) ...[
            IconButton(
              tooltip: 'Bearbeiten',
              icon: const Icon(Icons.edit_rounded),
              onPressed: _edit,
            ),
            IconButton(
              tooltip: 'Löschen',
              icon: const Icon(Icons.delete_rounded),
              onPressed: _delete,
            ),
          ],
        ],
        body: _loading && recipe == null
            ? const Center(child: CircularProgressIndicator())
            : recipe == null
                ? const Center(child: Text('Rezept nicht gefunden.'))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      children: [
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.icecream_rounded, color: cs.primary),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(recipe.title, style: theme.textTheme.titleLarge),
                                    ),
                                  ],
                                ),
                                if ((recipe.description ?? '').trim().isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Text(recipe.description!),
                                ],
                                if ((recipe.createdByDisplayName ?? '').trim().isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Von ${recipe.createdByDisplayName}',
                                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                  ),
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
                                Text('Zutaten', style: theme.textTheme.titleSmall),
                                const SizedBox(height: 8),
                                if (recipe.ingredients.isEmpty)
                                  Text('Keine Zutaten angegeben.', style: theme.textTheme.bodyMedium)
                                else
                                  for (final ing in recipe.ingredients)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 2),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.circle, size: 6),
                                          const SizedBox(width: 8),
                                          Expanded(child: Text(ing.name)),
                                          if ((ing.amount ?? '').trim().isNotEmpty)
                                            Text(
                                              ing.amount!,
                                              style: theme.textTheme.bodyMedium?.copyWith(
                                                color: cs.onSurfaceVariant,
                                              ),
                                            ),
                                        ],
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
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: StarRatingDisplay(
                                        average: recipe.ratingSummary.average,
                                        count: recipe.ratingSummary.count,
                                        size: 22,
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: () => setState(() => _showRatingInput = !_showRatingInput),
                                      icon: Icon(_hasMyRating ? Icons.edit_rounded : Icons.star_rounded),
                                      label: Text(_hasMyRating ? 'Bewertung bearbeiten' : 'Bewerten'),
                                    ),
                                  ],
                                ),
                                if (_showRatingInput) ...[
                                  const Divider(height: 24),
                                  StarRatingInput(
                                    stars: _myStars,
                                    onChanged: _rating
                                        ? (_) {}
                                        : (v) => setState(() => _myStars = v),
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _commentCtrl,
                                    enabled: !_rating,
                                    decoration: const InputDecoration(
                                      labelText: 'Kommentar (optional)',
                                    ),
                                    maxLines: 2,
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: FilledButton.icon(
                                          onPressed: _rating ? null : _submitRating,
                                          icon: const Icon(Icons.star_rounded),
                                          label: const Text('Bewertung speichern'),
                                        ),
                                      ),
                                      if (_hasMyRating) ...[
                                        const SizedBox(width: 8),
                                        IconButton(
                                          tooltip: 'Bewertung löschen',
                                          onPressed: _rating ? null : _deleteRating,
                                          icon: const Icon(Icons.delete_outline_rounded),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                                const Divider(height: 24),
                                Text(
                                  'Bewertungen (${recipe.ratings.length})',
                                  style: theme.textTheme.titleSmall,
                                ),
                                const SizedBox(height: 8),
                                if (recipe.ratings.isEmpty)
                                  Text('Noch keine Bewertungen.', style: theme.textTheme.bodyMedium)
                                else
                                  for (final rating in recipe.ratings)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 6),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  rating.displayName,
                                                  style: theme.textTheme.bodyMedium?.copyWith(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                _formatDate(rating.updatedAt),
                                                style: theme.textTheme.bodySmall?.copyWith(
                                                  color: cs.onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          StarRatingDisplay(
                                            average: rating.stars.toDouble(),
                                            count: 1,
                                            size: 16,
                                            showLabel: false,
                                          ),
                                          if ((rating.comment ?? '').trim().isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(rating.comment!),
                                          ],
                                        ],
                                      ),
                                    ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}
