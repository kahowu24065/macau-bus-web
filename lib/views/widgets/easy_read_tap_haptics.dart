import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Light haptic on taps. Scrolls move far enough that they do not buzz.
/// Mounted only while easy read mode is on.
class EasyReadTapHaptics extends StatefulWidget {
  const EasyReadTapHaptics({super.key, required this.child});

  final Widget child;

  @override
  State<EasyReadTapHaptics> createState() => _EasyReadTapHapticsState();
}

class _EasyReadTapHapticsState extends State<EasyReadTapHaptics> {
  Offset? _down;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) => _down = event.position,
      onPointerCancel: (_) => _down = null,
      onPointerUp: (event) {
        final start = _down;
        _down = null;
        if (start == null) return;
        if ((event.position - start).distance > 18) return;
        HapticFeedback.lightImpact();
      },
      child: widget.child,
    );
  }
}
