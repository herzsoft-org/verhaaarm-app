import 'package:flutter/material.dart';

/// An [IconButton] that swaps its icon for a small spinner while [busy] is
/// true, keeping the same footprint. Used in app bars to signal background
/// work (reload, save, ...) without shifting page content the way an inline
/// progress bar would.
class BusyIconButton extends StatelessWidget {
  final bool busy;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const BusyIconButton({
    super.key,
    required this.busy,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon),
      onPressed: busy ? null : onPressed,
    );
  }
}
