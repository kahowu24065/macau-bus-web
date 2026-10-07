import 'package:flutter/material.dart';

import '../../theme/easy_read_theme.dart';
import '../../utils/easy_read_access.dart';

/// Holds the theme from before easy read overrides, so chrome can opt out.
class EasyReadChrome extends InheritedWidget {
  const EasyReadChrome({
    super.key,
    required this.baseTheme,
    required super.child,
  });

  final ThemeData baseTheme;

  static ThemeData? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<EasyReadChrome>()?.baseTheme;
  }

  @override
  bool updateShouldNotify(EasyReadChrome oldWidget) =>
      oldWidget.baseTheme != baseTheme;
}

/// Keeps an existing header on the normal text scale and theme.
/// When easy read mode is off this returns [child] unchanged.
class PreserveChrome extends StatelessWidget {
  const PreserveChrome({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!EasyReadAccess.enabled(context)) return child;
    final mq = MediaQuery.of(context);
    final restored = MediaQuery(
      data: mq.copyWith(textScaler: EasyReadTheme.undoTextScale(mq.textScaler)),
      child: child,
    );
    final base = EasyReadChrome.maybeOf(context);
    if (base == null) return restored;
    return Theme(data: base, child: restored);
  }
}
