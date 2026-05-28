import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/dtos.dart';

typedef LiveEventReactionCallback =
    Future<void> Function(LiveEventReactionType type);

class LiveEventReactionButtons extends StatelessWidget {
  final LiveEventReactionSummary reactions;
  final LiveEventReactionCallback? onToggle;
  final Set<LiveEventReactionType> pendingTypes;
  final bool emphaticLabels;

  const LiveEventReactionButtons({
    super.key,
    required this.reactions,
    this.onToggle,
    this.pendingTypes = const {},
    this.emphaticLabels = false,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        LiveEventReactionChip(
          label: emphaticLabels ? 'Prost!' : 'Prost',
          icon: Symbols.sports_bar,
          count: reactions.prostCount,
          selected: reactions.reactedProst,
          pending: pendingTypes.contains(LiveEventReactionType.prost),
          onPressed: onToggle == null
              ? null
              : () => onToggle!(LiveEventReactionType.prost),
        ),
        LiveEventReactionChip(
          label: emphaticLabels ? 'Ich komme!' : 'Ich komme',
          icon: Symbols.directions_run,
          count: reactions.ichKommeCount,
          selected: reactions.reactedIchKomme,
          pending: pendingTypes.contains(LiveEventReactionType.ichKomme),
          onPressed: onToggle == null
              ? null
              : () => onToggle!(LiveEventReactionType.ichKomme),
        ),
      ],
    );
  }
}

class LiveEventReactionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final int count;
  final bool selected;
  final bool pending;
  final VoidCallback? onPressed;

  const LiveEventReactionChip({
    super.key,
    required this.label,
    required this.icon,
    required this.count,
    required this.selected,
    required this.pending,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = Theme.of(context).colorScheme;
    final enabled = !pending && onPressed != null;
    final foreground = selected ? cs.primary : cs.onSurfaceVariant;
    final background = selected
        ? cs.primaryContainer.withValues(alpha: 0.58)
        : cs.surfaceContainerHighest.withValues(alpha: 0.55);
    final borderColor = selected
        ? cs.primary.withValues(alpha: 0.28)
        : cs.outlineVariant.withValues(alpha: 0.28);

    return Tooltip(
      message: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: enabled ? onPressed : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            constraints: const BoxConstraints(minHeight: 30),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: borderColor),
            ),
            child: Opacity(
              opacity: enabled || pending ? 1 : 0.62,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (pending)
                    SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: foreground,
                      ),
                    )
                  else
                    Icon(icon, size: 16, color: foreground),
                  const SizedBox(width: 5),
                  Text(
                    '$label · $count',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: selected ? cs.onPrimaryContainer : foreground,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
