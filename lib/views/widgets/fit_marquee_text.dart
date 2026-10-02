import 'package:flutter/material.dart';
import 'package:text_scroll/text_scroll.dart';

/// Single-line text that only becomes a marquee (TextScroll) when it does not
/// fit. TextScroll caches the first viewport width it sees; if the layout later
/// gets narrower it keeps a stale min-width, decides it "needs scrolling",
/// doubles the text ("外港碼頭 外港碼頭") and then cannot move it. Rendering a
/// plain Text when the string fits, and keying TextScroll by text + width,
/// avoids that stale state.
class FitMarqueeText extends StatelessWidget {
  final String text;
  final TextStyle style;

  const FitMarqueeText(this.text, {super.key, required this.style});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: DefaultTextStyle.of(context).style.merge(style)),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final fits = !constraints.hasBoundedWidth || painter.width <= constraints.maxWidth;
        if (fits) {
          return Text(text, style: style, maxLines: 1, softWrap: false, overflow: TextOverflow.clip);
        }
        return TextScroll(
          text,
          key: ValueKey('$text|${constraints.maxWidth.round()}'),
          mode: TextScrollMode.endless,
          velocity: const Velocity(pixelsPerSecond: Offset(35, 0)),
          delayBefore: const Duration(seconds: 2),
          pauseBetween: const Duration(seconds: 2),
          fadedBorder: true,
          fadedBorderWidth: 0.05,
          style: style,
          selectable: false,
        );
      },
    );
  }
}
