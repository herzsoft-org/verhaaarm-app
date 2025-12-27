import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class MobileWebKeyboardFix extends StatefulWidget {
  final Widget child;

  const MobileWebKeyboardFix({super.key, required this.child});

  @override
  State<MobileWebKeyboardFix> createState() => _MobileWebKeyboardFixState();
}

class _MobileWebKeyboardFixState extends State<MobileWebKeyboardFix>
    with WidgetsBindingObserver {
  double _lastInset = 0;

  bool get _isMobileWeb {
    return kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android);
  }

  double _bottomInsetLogical() {
    // More reliable than MediaQuery inside didChangeMetrics during transitions on web.
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    return view.viewInsets.bottom / view.devicePixelRatio;
  }

  @override
  void initState() {
    super.initState();
    if (_isMobileWeb) {
      WidgetsBinding.instance.addObserver(this);
      _lastInset = _bottomInsetLogical();
    }
  }

  @override
  void dispose() {
    if (_isMobileWeb) {
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (!_isMobileWeb || !mounted) return;

    final inset = _bottomInsetLogical();

    // Keyboard just closed: nudge Flutter Web to settle layout.
    if (_lastInset > 0 && inset == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        FocusManager.instance.primaryFocus?.unfocus();

        // Force a rebuild after the viewport change; mitigates the "stuck white gap".
        setState(() {});
      });
    }

    _lastInset = inset;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
