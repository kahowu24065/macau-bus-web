import 'package:flutter/material.dart';

import '../../theme/elderly_theme.dart';
import '../../utils/elderly_access.dart';

/// Holds the theme from before elderly overrides, so chrome can opt out.
class ElderlyChrome extends InheritedWidget {
  const ElderlyChrome({
    super.key,
    required this.baseTheme,
    required super.child,
  });

  final ThemeData baseTheme;

  static ThemeData? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ElderlyChrome>()?.baseTheme;
  }

  @override
  bool updateShouldNotify(ElderlyChrome oldWidget) =>
      oldWidget.baseTheme != baseTheme;
}

/// Keeps an existing header on the normal text scale and theme.
/// When elderly mode is off this returns [child] unchanged.
class PreserveChrome extends StatelessWidget {
  const PreserveChrome({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!ElderlyAccess.enabled(context)) return child;
    final mq = MediaQuery.of(context);
    final restored = MediaQuery(
      data: mq.copyWith(textScaler: ElderlyTheme.undoTextScale(mq.textScaler)),
      child: child,
    );
    final base = ElderlyChrome.maybeOf(context);
    if (base == null) return restored;
    return Theme(data: base, child: restored);
  }
}
