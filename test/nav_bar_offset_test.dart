import 'package:flutter_test/flutter_test.dart';
import 'package:macau_bus_app/views/widgets/route_liquid_glass_nav.dart';

void main() {
  test('iOS docks the capsule above a slim home-indicator clearance', () {
    const safe = 34.0;
    final offset = RouteLiquidGlassNavStyle.barBottomOffset(safe, ios: true);
    final margin = RouteLiquidGlassNavStyle.tabBarMarginBottom(
      paddingBottom: safe,
      viewPaddingBottom: safe,
      ios: true,
    );

    expect(offset, RouteLiquidGlassNavStyle.homeIndicatorClearance);
    // Package adds the safe inset back onto margin.bottom.
    expect(margin + safe, offset);
    expect(offset, lessThan(safe));
  });

  test('iOS with no home indicator sits on the screen edge', () {
    expect(RouteLiquidGlassNavStyle.barBottomOffset(0, ios: true), 0);
    expect(
      RouteLiquidGlassNavStyle.tabBarMarginBottom(
        paddingBottom: 0,
        viewPaddingBottom: 0,
        ios: true,
      ),
      0,
    );
  });

  test('Android keeps the full system-nav inset and drops the extra float', () {
    const safe = 48.0;
    final offset = RouteLiquidGlassNavStyle.barBottomOffset(safe, ios: false);
    final margin = RouteLiquidGlassNavStyle.tabBarMarginBottom(
      paddingBottom: safe,
      viewPaddingBottom: safe,
      ios: false,
    );

    expect(offset, safe);
    expect(margin + safe, offset);
    expect(margin, 0);
  });
}
