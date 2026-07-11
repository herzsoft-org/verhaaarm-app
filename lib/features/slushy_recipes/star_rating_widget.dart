import 'package:flutter/material.dart';

/// Readonly display of an average star rating, e.g. "4.3 (12)".
class StarRatingDisplay extends StatelessWidget {
  final double average;
  final int count;
  final double size;
  final bool showLabel;

  const StarRatingDisplay({
    super.key,
    required this.average,
    required this.count,
    this.size = 18,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final rounded = average.round().clamp(0, 5);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            i <= rounded ? Icons.star_rounded : Icons.star_border_rounded,
            size: size,
            color: count == 0 ? cs.onSurfaceVariant : cs.primary,
          ),
        if (showLabel) ...[
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              count == 0 ? 'Noch keine Bewertungen' : '${average.toStringAsFixed(1)} ($count)',
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ],
    );
  }
}

/// Tappable 1-5 star input for the current user's own rating.
class StarRatingInput extends StatelessWidget {
  final int stars;
  final ValueChanged<int> onChanged;
  final double size;

  const StarRatingInput({
    super.key,
    required this.stars,
    required this.onChanged,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            visualDensity: VisualDensity.compact,
            onPressed: () => onChanged(i),
            icon: Icon(
              i <= stars ? Icons.star_rounded : Icons.star_border_rounded,
              size: size,
              color: cs.primary,
            ),
          ),
      ],
    );
  }
}
