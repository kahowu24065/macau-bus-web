import 'package:flutter_test/flutter_test.dart';
import 'package:macau_bus_app/views/screens/home_screen.dart';

void main() {
  bool show({
    bool isWeb = false,
    bool isPro = false,
    bool showMapView = false,
    int selectedIndex = 0,
    bool isPlanningRoute = false,
  }) {
    return showHomeBannerSlot(
      isWeb: isWeb,
      isPro: isPro,
      showMapView: showMapView,
      selectedIndex: selectedIndex,
      isPlanningRoute: isPlanningRoute,
    );
  }

  test('hides the banner slot on map, station, and route planning', () {
    expect(show(showMapView: true, selectedIndex: 0), isFalse);
    expect(show(selectedIndex: 2), isFalse);
    expect(show(selectedIndex: 3), isFalse);
    expect(show(selectedIndex: 0, isPlanningRoute: true), isFalse);
    expect(show(showMapView: true, selectedIndex: 2, isPlanningRoute: true), isFalse);
  });

  test('keeps the banner slot on search, routes, favorites, and settings', () {
    expect(show(selectedIndex: 0), isTrue);
    expect(show(selectedIndex: 1), isTrue);
    expect(show(selectedIndex: 4), isTrue);
    expect(show(selectedIndex: 5), isTrue);
  });

  test('pro and web never reserve a banner slot', () {
    expect(show(isPro: true, selectedIndex: 0), isFalse);
    expect(show(isWeb: true, selectedIndex: 1), isFalse);
    expect(show(isPro: true, showMapView: true), isFalse);
  });
}
