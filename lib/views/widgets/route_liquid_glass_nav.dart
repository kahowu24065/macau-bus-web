// Drop into your 「尋找路線」 app (e.g. lib/widgets/route_liquid_glass_nav.dart)
// Requires: liquid_glass_easy: ^4.3.1 in pubspec.yaml
//
// Tint plate (no BackdropFilter — that blurs the photo before the lens)
// + Impeller refractive capsule on top.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../utils/easy_read_access.dart';

/// Accent for selected tab — matches app amber.
const Color kRouteLgAccent = Color(0xFFFFC107);

class RouteLiquidGlassNavItem {
  const RouteLiquidGlassNavItem({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

/// Pre-tuned styles for the liquid-glass bottom nav.
abstract final class RouteLiquidGlassNavStyle {
  static const double barHeight = 68;

  /// Taller bar while easy read mode is on. [barHeight] stays the normal size.
  static const double easyReadBarHeight = 88;

  static double barHeightOf(BuildContext context) =>
      EasyReadAccess.enabled(context) ? easyReadBarHeight : barHeight;
  /// Rounder end caps now that the bar is taller.
  static const double kSharedCornerRadius = 32;

  /// Extra lift used before 1.0.20, added on top of the safe-area inset.
  static const double legacyFloatMargin = 18;

  /// Flush-bottom clearance used in 1.0.20 (too low on TestFlight).
  static const double homeIndicatorClearance = 8;

  /// Standard AdMob [AdSize.banner] height (logical px).
  static const double bannerAdHeight = 50;

  static bool isIos(BuildContext context) {
    if (kIsWeb) return false;
    return Theme.of(context).platform == TargetPlatform.iOS;
  }

  /// Distance from the physical bottom to the capsule.
  ///
  /// iOS: halfway between the old float (`legacyFloatMargin` + safe area)
  /// and the 1.0.20 flush clearance. Other platforms keep the full system
  /// inset so a 3-button navigation bar stays clear.
  static double barBottomOffset(double safeBottom, {required bool ios}) {
    if (safeBottom <= 0) return 0;
    if (ios) {
      final floating = legacyFloatMargin + safeBottom;
      return (floating + homeIndicatorClearance) / 2;
    }
    return safeBottom;
  }

  /// [LiquidGlassTabBar] adds [paddingBottom] on top of `margin.bottom`.
  /// Subtract it so the capsule lands on [barBottomOffset].
  static double tabBarMarginBottom({
    required double paddingBottom,
    required double viewPaddingBottom,
    required bool ios,
  }) =>
      barBottomOffset(viewPaddingBottom, ios: ios) - paddingBottom;

  /// Space from the physical screen bottom to the top of the docked bar
  /// (and optional banner sitting above it).
  static double bottomReserve(
    BuildContext context, {
    double bannerHeight = 0,
  }) =>
      barHeightOf(context) +
      barBottomOffset(
        MediaQuery.viewPaddingOf(context).bottom,
        ios: isIos(context),
      ) +
      bannerHeight;

  /// Bottom inset so a floating SnackBar sits flush on the nav (or ad) top.
  static EdgeInsets snackBarMargin(BuildContext context) => EdgeInsets.fromLTRB(
        16,
        0,
        16,
        bottomReserve(
          context,
          bannerHeight: BannerSlotHeight.of(context),
        ),
      );

  static SnackBar snackBar({
    required BuildContext context,
    required Widget content,
    Color? backgroundColor,
    Duration duration = const Duration(seconds: 2),
  }) {
    return SnackBar(
      content: content,
      backgroundColor: backgroundColor,
      duration: duration,
      behavior: SnackBarBehavior.floating,
      margin: snackBarMargin(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  // ★★★ 導覽列顏色／透明度 — 只改呢度（對齊 reference 片）★★★
  // Flutter 磨砂底，唔經 liquid_glass shader，改完一定跟到。
  // 半透 frosted glass：約 25% 填色 + 中等 blur，地圖／內容要清楚透出。
  // AARRGGBB 前面兩位 = alpha（FF=全實）。改完 Hot Restart。
  static const Color kDarkGlassFill = Color(0x401A1A1E); // ~25% dark frost
  static const Color kLightGlassFill = Color(0x66FFFFFF); // icy white frost

  /// Capsule tint. Light mode must stay white — a gray wash reads as dirty.
  static LiquidGlassStyle clearBarStyle({required bool isDark}) => LiquidGlassStyle(
        shape: LiquidGlassShape.continuousRoundedRectangle(
          cornerRadius: kSharedCornerRadius,
          clipQuality: LiquidGlassClipQuality.exact,
          borderWidth: 0.9,
          lightIntensity: isDark ? 0.7 : 1.05,
          lightDirection: 55,
          lightColor: const Color(0xCCFFFFFF),
          borderType: OpticalBorder(
            borderSaturation: isDark ? 0.8 : 1.15,
            ambientIntensity: isDark ? 0.6 : 0.85,
            borderSolidity: isDark ? 0.25 : 0.12,
          ),
        ),
        adaptivity: LiquidGlassAdaptivity.none,
        appearance: LiquidGlassAppearance(
          color: isDark
              ? const Color.fromARGB(90, 28, 28, 32)
              : const Color.fromARGB(70, 255, 255, 255),
          enableInnerRadiusTransparent: false,
          shadow: const LiquidGlassShadow(blur: 0, opacity: 0),
        ),
        refraction: const LiquidGlassRefraction(
          magnification: 1.06,
          chromaticAberration: 0.01,
          refractionType: OpticalRefraction(
            refraction: 1.5,
            refractionWidth: 5,
            depth: 0.38,
          ),
        ),
      );

  /// Selection lens — same end radius as the bar (full stadium semicircle).
  static LiquidGlassShape lensShape() =>
      LiquidGlassShape.continuousRoundedRectangle(
        cornerRadius: kSharedCornerRadius,
        clipQuality: LiquidGlassClipQuality.exact,
        borderWidth: 1.05,
        lightIntensity: 1.55,
        lightDirection: 42,
        lightColor: const Color(0xFFFFFFFF),
        borderType: const OpticalBorder(
          borderSaturation: 1.45,
          ambientIntensity: 1.1,
          borderSolidity: 0.0,
        ),
      );

  static LiquidGlassTabPillStyle get pillStyle => LiquidGlassTabPillStyle(
        mode: LiquidGlassPillMode.both,
        growHeight: 0,
        distortion: 0.18,
        distortionWidth: 22,
        magnification: 1.4,
        travelStiffness: 180,
        travelDamping: 18,
        motion: const LiquidGlassLensMotionSpec(
          sampleWindow: 0.28,
          sensitivity: 0.00014,
          maxDeformation: 0.36,
          responseTime: 0.12,
        ),
        glassStyle: LiquidGlassStyle(
          shape: lensShape(),
          adaptivity: LiquidGlassAdaptivity.none,
          appearance: const LiquidGlassAppearance(
            color: Color.fromARGB(0, 0, 0, 0),
            blur: LiquidGlassBlur(sigmaX: 0.5, sigmaY: 0.5),
            shadow: LiquidGlassShadow(blur: 12, opacity: 0.30, inset: 0),
          ),
          refraction: const LiquidGlassRefraction(
            distortion: 0.2,
            distortionWidth: 20,
            magnification: 1.4,
            chromaticAberration: 0.014,
          ),
        ),
        rest: LiquidGlassStyle(
          shape: lensShape(),
          adaptivity: LiquidGlassAdaptivity.none,
          appearance: const LiquidGlassAppearance(
            color: Color(0x33FFFFFF),
            shadow: LiquidGlassShadow(blur: 8, opacity: 0.14, inset: 0),
          ),
        ),
      );

  static LiquidGlassTabItemStyle itemStyle({
    Color selected = kRouteLgAccent,
    Color unselected = Colors.white,
    bool easyRead = false,
  }) =>
      LiquidGlassTabItemStyle(
        selectedColor: selected,
        unselectedColor: unselected,
        iconSize: easyRead ? 32 : 24,
        labelFontSize: easyRead ? 14 : 11,
        iconLabelGap: easyRead ? 4 : 3,
        underGlassIconSize: easyRead ? 34 : 26,
        underGlassLabelFontSize: easyRead ? 14 : 11,
        selectedFontWeight: FontWeight.w700,
        unselectedFontWeight: easyRead ? FontWeight.w700 : FontWeight.w500,
      );

  static List<LiquidGlassTabBarItem> toItems(
    List<RouteLiquidGlassNavItem> items, {
    bool easyRead = false,
  }) =>
      [
        for (final t in items)
          LiquidGlassTabBarItem(
            label: t.label,
            iconBuilder: (context, i) => Icon(
              t.icon,
              size: easyRead
                  ? (i.underGlass == true ? 36 : 32)
                  : (i.underGlass == true ? 28 : 24),
              color: i.color,
            ),
          ),
      ];
}

/// Actual on-screen banner height (0 when Pro / not loaded).
class BannerSlotHeight extends InheritedWidget {
  const BannerSlotHeight({
    super.key,
    required this.height,
    required super.child,
  });

  final double height;

  static double of(BuildContext context) {
    final element =
        context.getElementForInheritedWidgetOfExactType<BannerSlotHeight>();
    if (element == null) return 0;
    return (element.widget as BannerSlotHeight).height;
  }

  @override
  bool updateShouldNotify(BannerSlotHeight oldWidget) =>
      oldWidget.height != height;
}

/// Reliable dark-glass plate under the refractive bar (opacity always works).
class _DarkGlassPlate extends StatelessWidget {
  const _DarkGlassPlate({
    required this.width,
    required this.height,
    required this.bottom,
    required this.fill,
    required this.isDark,
  });

  final double width;
  final double height;
  final double bottom;
  final Color fill;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(
      RouteLiquidGlassNavStyle.kSharedCornerRadius,
    );
    return Positioned(
      left: 0,
      right: 0,
      bottom: bottom,
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.08),
                blurRadius: isDark ? 18 : 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                borderRadius: radius,
                color: fill,
                border: Border.all(
                  color: Colors.white.withValues(alpha: isDark ? 0.22 : 0.55),
                  width: 0.9,
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.lerp(fill, Colors.white, isDark ? 0.12 : 0.35)!,
                    fill,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen overlay: frost plate + refractive liquid-glass tab bar.
class RouteLiquidGlassNav extends StatelessWidget {
  const RouteLiquidGlassNav({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onChanged,
    this.onReselect,
    this.width,
    this.selectedColor = kRouteLgAccent,
    this.unselectedColor = Colors.white,
    this.isDark = true,
  });

  final List<RouteLiquidGlassNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  /// Tap on the already-selected tab (the package bar only reports changes).
  final ValueChanged<int>? onReselect;
  final double? width;
  final Color selectedColor;
  final Color unselectedColor;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    // Near full-width so each tab cell is wide enough for PT labels.
    final easyRead = EasyReadAccess.enabled(context);
    final w = width ??
        (MediaQuery.sizeOf(context).width - 20).clamp(300.0, 520.0);
    final h = easyRead
        ? RouteLiquidGlassNavStyle.easyReadBarHeight
        : RouteLiquidGlassNavStyle.barHeight;
    final ios = RouteLiquidGlassNavStyle.isIos(context);
    // Dock the capsule. The package adds padding.bottom on top of
    // margin.bottom; cancel that so we don't stack a second inset
    // (that stack was the empty black gap under the pill).
    final bottom = RouteLiquidGlassNavStyle.barBottomOffset(
      MediaQuery.viewPaddingOf(context).bottom,
      ios: ios,
    );
    final barMargin = EdgeInsets.only(
      bottom: RouteLiquidGlassNavStyle.tabBarMarginBottom(
        paddingBottom: MediaQuery.paddingOf(context).bottom,
        viewPaddingBottom: MediaQuery.viewPaddingOf(context).bottom,
        ios: ios,
      ),
    );
    final fill = isDark
        ? RouteLiquidGlassNavStyle.kDarkGlassFill
        : RouteLiquidGlassNavStyle.kLightGlassFill;

    final stack = Stack(
      fit: StackFit.expand,
      children: [
        // 1) Your controllable dark glass (always respects kDarkGlassFill).
        _DarkGlassPlate(
          width: w,
          height: h,
          bottom: bottom,
          fill: fill,
          isDark: isDark,
        ),
        // 2) Package bar: clear capsule + refractive selection lens.
        LiquidGlassTabBar.withImpeller(
          items: RouteLiquidGlassNavStyle.toItems(items, easyRead: easyRead),
          selectedIndex: selectedIndex,
          onChanged: onChanged,
          width: w,
          height: h,
          margin: barMargin,
          itemPadding: 7,
          style: RouteLiquidGlassNavStyle.clearBarStyle(isDark: isDark),
          itemStyle: RouteLiquidGlassNavStyle.itemStyle(
            selected: selectedColor,
            unselected: unselectedColor,
            easyRead: easyRead,
          ),
          pillStyle: RouteLiquidGlassNavStyle.pillStyle,
        ),
      ],
    );
    if (onReselect == null) return stack;
    // Re-tap detection: a Listener sees raw pointers without joining the
    // gesture arena, so the bar's own tap/drag handling is untouched.
    Offset? down;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) => down = e.position,
      onPointerUp: (e) {
        final start = down;
        down = null;
        if (start == null || (e.position - start).distance > 12) return;
        final size = MediaQuery.sizeOf(context);
        final left = (size.width - w) / 2;
        final top = size.height - bottom - h;
        final p = e.position;
        if (p.dx < left || p.dx > left + w || p.dy < top || p.dy > top + h) return;
        final idx = ((p.dx - left) / (w / items.length)).floor().clamp(0, items.length - 1);
        if (idx == selectedIndex) onReselect!(idx);
      },
      child: stack,
    );
  }
}
