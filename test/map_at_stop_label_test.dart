import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:macau_bus_app/controllers/bus_controller.dart';
import 'package:macau_bus_app/controllers/easy_read_mode_controller.dart';
import 'package:macau_bus_app/controllers/language_controller.dart';
import 'package:macau_bus_app/controllers/location_controller.dart';
import 'package:macau_bus_app/controllers/navigation_controller.dart';
import 'package:macau_bus_app/models/bus.dart';
import 'package:macau_bus_app/models/bus_stop.dart';
import 'package:macau_bus_app/services/open_data_config.dart';
import 'package:macau_bus_app/utils/bus_marker_bearing.dart';
import 'package:macau_bus_app/views/screens/map_screen.dart';

class _OfflineHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    throw const SocketException('widget test is offline');
  }
}

BusStop _stop(int seq) {
  return BusStop(
    seq: seq,
    name: '站$seq',
    nameZh: '站$seq',
    nameZhHans: '站$seq',
    namePt: 'Paragem $seq',
    nameEn: 'Stop $seq',
    code: 'M$seq',
    lat: 22.20 + (seq - 1) * 0.003,
    lng: 113.54,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final previousHttp = HttpOverrides.current;

  setUp(() {
    HttpOverrides.global = _OfflineHttpOverrides();
    OpenDataConfig.instance.debugApply(configRealtime: true, etaRealtime: true);
  });

  tearDown(() {
    HttpOverrides.global = previousHttp;
    OpenDataConfig.instance.debugReset();
  });

  test('bearing follows the route shape and the chevron survives map rotation', () {
    const corner = LatLng(22.21, 113.54);
    const eastEnd = LatLng(22.21, 113.55);
    final bent = <LatLng>[
      const LatLng(22.20, 113.54),
      corner,
      eastEnd,
    ];
    final onNorthLeg = busTravelBearingDegrees(
      position: const LatLng(22.205, 113.54),
      nextStop: eastEnd,
      route: bent,
    );
    expect(onNorthLeg, isNotNull);
    expect(onNorthLeg!, closeTo(0, 8));

    final straight = busTravelBearingDegrees(
      position: corner,
      nextStop: const LatLng(22.21, 113.56),
      route: const [],
    );
    expect(straight, isNotNull);
    expect(straight!, closeTo(90, 8));

    expect(
      busChevronRadians(bearingDegrees: 0, mapRotationDegrees: 0),
      closeTo(0, 0.001),
    );
    expect(
      busChevronRadians(bearingDegrees: 90, mapRotationDegrees: 0),
      closeTo(math.pi / 2, 0.001),
    );
    expect(
      busChevronRadians(bearingDegrees: 0, mapRotationDegrees: 90),
      closeTo(math.pi / 2, 0.001),
    );
    expect(
      busChevronRadians(bearingDegrees: 90, mapRotationDegrees: 90),
      closeTo(math.pi, 0.001),
    );
  });

  test('easy read info tab sits beside the route and clears the icon', () {
    const icon = 44 * 1.3;
    const tabWidth = 120.0;
    const tabHeight = 70.0;
    const gap = 6.0;
    final beside = busInfoTabCenter(
      chevronRadians: 0,
      iconSize: icon,
      tabWidth: tabWidth,
      tabHeight: tabHeight,
      gap: gap,
    );
    expect(beside.dx, closeTo(icon / 2 + tabWidth / 2 + gap, 0.01));
    expect(beside.dy, closeTo(0, 0.01));
    expect(_boxesOverlap(icon, tabWidth, tabHeight, beside.dx, beside.dy), isFalse);
    expect(_pointInTab(0, -40, beside.dx, beside.dy, tabWidth, tabHeight), isFalse);

    final eastbound = busInfoTabCenter(
      chevronRadians: math.pi / 2,
      iconSize: icon,
      tabWidth: tabWidth,
      tabHeight: tabHeight,
      gap: gap,
    );
    expect(eastbound.dx, closeTo(0, 0.01));
    expect(eastbound.dy, greaterThan(icon / 2));

    final above = busMarkerTabCenter(
      easyRead: false,
      iconSize: 44,
      tabWidth: tabWidth,
      tabHeight: tabHeight,
      gap: gap,
      chevronRadians: 0,
    );
    expect(above.dx, 0);
    expect(above.dy, lessThan(0));
  });

  testWidgets('map bus markers open one tab and keep the direction arrow', (tester) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bus = BusController();
    bus.setRoute('3');
    bus.stopsList = [for (var i = 1; i <= 3; i++) _stop(i)];
    bus.selectedStopSeq = 2;
    bus.allBusesList = const [
      Bus(
        busLicense: 'MB-HERE',
        lat: 22.203,
        lng: 113.54,
        speed: 0,
        currentStopSeq: 2,
        atStop: true,
      ),
      Bus(
        busLicense: 'MB-MOVE',
        lat: 22.20,
        lng: 113.54,
        speed: 28,
        currentStopSeq: 1,
        atStop: false,
      ),
    ];
    addTearDown(bus.dispose);

    Future<void> pump({
      required String lang,
      required bool easyRead,
      Brightness brightness = Brightness.dark,
      double textScale = 1,
    }) async {
      SharedPreferences.setMockInitialValues({'language_code': lang});
      final language = LanguageController();
      final location = LocationController();
      final navigation = NavigationController();
      final easy = EasyReadModeController.fixed(easyRead);
      addTearDown(language.dispose);
      addTearDown(location.dispose);
      addTearDown(navigation.dispose);
      addTearDown(easy.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<BusController>.value(value: bus),
            ChangeNotifierProvider<LanguageController>.value(value: language),
            ChangeNotifierProvider<LocationController>.value(value: location),
            ChangeNotifierProvider<NavigationController>.value(value: navigation),
            ChangeNotifierProvider<EasyReadModeController>.value(value: easy),
          ],
          child: MaterialApp(
            theme: ThemeData(brightness: brightness),
            builder: (context, child) {
              final mq = MediaQuery.of(context);
              return MediaQuery(
                data: mq.copyWith(textScaler: TextScaler.linear(textScale)),
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: MapScreen(key: ValueKey('$lang-$easyRead-$brightness-$textScale')),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> openBus(String plate) async {
      await tester.tap(find.byKey(ValueKey('bus-hit-$plate')));
      await tester.pump();
    }

    await pump(lang: 'zh', easyRead: false);
    expect(find.text('MB-HERE'), findsNothing);
    expect(find.text('即將到站 / 到站中'), findsNothing);
    expect(find.text('已到站'), findsNothing);
    expect(tester.getSize(find.byKey(const ValueKey('bus-hit-MB-HERE'))).shortestSide, 44);
    expect(tester.getSize(find.byKey(const ValueKey('bus-hit-MB-MOVE'))).shortestSide, 44);
    expect(_coloredBusIcon(tester, 'MB-HERE').size, 26);
    expect(_chevronIcon(tester, 'MB-MOVE').size, 18);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Icon && widget.icon == Icons.directions_bus && widget.color == Colors.orangeAccent,
      ),
      findsOneWidget,
    );

    final moveBearing = busTravelBearingDegrees(
      position: const LatLng(22.20, 113.54),
      nextStop: const LatLng(22.203, 113.54),
    );
    final turned = tester.widget<Transform>(find.byKey(const ValueKey('bus-chevron-MB-MOVE'))).transform.storage;
    expect(math.atan2(turned[1], turned[0]), closeTo(busChevronRadians(bearingDegrees: moveBearing!, mapRotationDegrees: 0), 0.15));

    await openBus('MB-HERE');
    expect(find.text('MB-HERE'), findsOneWidget);
    expect(find.text('即將到站 / 到站中'), findsOneWidget);
    expect(tester.widget<Text>(find.text('即將到站 / 到站中')).style?.color, Colors.deepOrange);
    expect(tester.widget<Text>(find.text('即將到站 / 到站中')).style?.fontSize, 12);
    expect(find.text('0km/h'), findsOneWidget);
    expect(find.text('MB-MOVE'), findsNothing);
    final hereIcon = tester.getCenter(find.byKey(const ValueKey('bus-hit-MB-HERE')));
    final hereTab = tester.getRect(find.byKey(const ValueKey('bus-tab-MB-HERE')));
    expect(hereTab.bottom, lessThanOrEqualTo(hereIcon.dy - 18));
    expect(hereTab.center.dx, closeTo(hereIcon.dx, 8));

    await openBus('MB-HERE');
    expect(find.text('MB-HERE'), findsNothing);
    expect(find.text('即將到站 / 到站中'), findsNothing);

    await openBus('MB-HERE');
    await openBus('MB-MOVE');
    expect(find.text('MB-HERE'), findsNothing);
    expect(find.text('即將到站 / 到站中'), findsNothing);
    expect(find.text('MB-MOVE'), findsOneWidget);
    expect(find.text('往 站2'), findsOneWidget);
    expect(find.text('28km/h'), findsOneWidget);

    final mapBox = tester.getRect(find.byType(FlutterMap));
    await tester.tapAt(mapBox.center + const Offset(-180, -120));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('MB-MOVE'), findsNothing);
    expect(find.text('往 站2'), findsNothing);

    const cases = [
      ('zh', false, '即將到站 / 到站中', '往 站2'),
      ('zhHans', false, '即将到站 / 到站中', '往 站2'),
      ('en', false, 'Arriving / At stop', 'To Stop 2'),
      ('pt', false, 'A chegar / Na paragem', 'Para Paragem 2'),
      ('zh', true, '即將到站', '往 站2'),
      ('zhHans', true, '即将到站', '往 站2'),
      ('en', true, 'Arriving soon', 'To Stop 2'),
      ('pt', true, 'A chegar', 'Para Paragem 2'),
    ];
    for (final item in cases) {
      await pump(lang: item.$1, easyRead: item.$2, brightness: item.$2 ? Brightness.light : Brightness.dark);
      expect(find.text(item.$3), findsNothing, reason: '${item.$1} closed');
      await openBus('MB-HERE');
      final label = find.text(item.$3);
      expect(label, findsOneWidget, reason: '${item.$1} easy=${item.$2}');
      expect(tester.widget<Text>(label).style?.color, Colors.deepOrange);
      expect(tester.widget<Text>(label).style?.fontSize, closeTo(item.$2 ? 12 * 1.3 : 12, 0.01));
      expect(find.text('已到站'), findsNothing);
      final tab = tester.widget<Container>(find.byKey(const ValueKey('bus-tab-MB-HERE')));
      expect((tab.decoration as BoxDecoration).color, Colors.white);
      final tabRect = tester.getRect(find.byKey(const ValueKey('bus-tab-MB-HERE')));
      final textRect = tester.getRect(label);
      expect(tabRect.inflate(1).contains(textRect.topLeft), isTrue);
      expect(tabRect.inflate(1).contains(textRect.bottomRight), isTrue);
      await openBus('MB-MOVE');
      expect(find.text(item.$4), findsOneWidget, reason: '${item.$1} direction');
      expect(find.text(item.$3), findsNothing);
    }

    await pump(lang: 'pt', easyRead: true, brightness: Brightness.light, textScale: 1.35);
    await openBus('MB-HERE');
    expect(find.text('A chegar'), findsOneWidget);
    final scaledTab = tester.getRect(find.byKey(const ValueKey('bus-tab-MB-HERE')));
    final scaledText = tester.getRect(find.text('A chegar'));
    expect(scaledTab.inflate(1).contains(scaledText.topLeft), isTrue);
    expect(scaledTab.inflate(1).contains(scaledText.bottomRight), isTrue);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('easy read map icons stay modest and the route stays in view', (tester) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bus = BusController();
    bus.setRoute('3');
    bus.stopsList = [for (var i = 1; i <= 3; i++) _stop(i)];
    bus.selectedStopSeq = 2;
    bus.allBusesList = const [
      Bus(
        busLicense: 'MB-HERE',
        lat: 22.203,
        lng: 113.54,
        speed: 0,
        currentStopSeq: 2,
        atStop: true,
      ),
      Bus(
        busLicense: 'MB-MOVE',
        lat: 22.20,
        lng: 113.54,
        speed: 28,
        currentStopSeq: 1,
        atStop: false,
      ),
    ];
    addTearDown(bus.dispose);

    Future<void> pump({required bool easyRead, double textScale = 1}) async {
      SharedPreferences.setMockInitialValues({'language_code': 'zh'});
      final language = LanguageController();
      final location = LocationController();
      final navigation = NavigationController();
      final easy = EasyReadModeController.fixed(easyRead);
      addTearDown(language.dispose);
      addTearDown(location.dispose);
      addTearDown(navigation.dispose);
      addTearDown(easy.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<BusController>.value(value: bus),
            ChangeNotifierProvider<LanguageController>.value(value: language),
            ChangeNotifierProvider<LocationController>.value(value: location),
            ChangeNotifierProvider<NavigationController>.value(value: navigation),
            ChangeNotifierProvider<EasyReadModeController>.value(value: easy),
          ],
          child: MaterialApp(
            builder: (context, child) {
              final mq = MediaQuery.of(context);
              return MediaQuery(
                data: mq.copyWith(textScaler: TextScaler.linear(textScale)),
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: MapScreen(key: ValueKey('scale-$easyRead-$textScale')),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    await pump(easyRead: true);
    final hit = tester.getSize(find.byKey(const ValueKey('bus-hit-MB-HERE')));
    expect(hit.shortestSide, inInclusiveRange(44 * 1.25, 44 * 1.35));
    expect(_coloredBusIcon(tester, 'MB-HERE').size, closeTo(26 * 1.3, 0.01));
    expect(_chevronIcon(tester, 'MB-MOVE').size, closeTo(18 * 1.3, 0.01));
    expect(tester.getSize(find.byKey(const ValueKey('stop-pin-3'))).width, 26);
    expect(tester.getSize(find.byKey(const ValueKey('stop-pin-2'))).width, 32);
    final hereHit = tester.getRect(find.byKey(const ValueKey('bus-hit-MB-HERE')));
    final stop3 = tester.getRect(find.byKey(const ValueKey('stop-pin-3')));
    expect(hereHit.overlaps(stop3), isFalse);

    await tester.tap(find.byKey(const ValueKey('bus-hit-MB-MOVE')));
    await tester.pump();
    final iconRect = tester.getRect(find.byKey(const ValueKey('bus-hit-MB-MOVE')));
    final tabRect = tester.getRect(find.byKey(const ValueKey('bus-tab-MB-MOVE')));
    expect(tabRect.overlaps(iconRect), isFalse);
    expect(tabRect.center.dx, greaterThan(iconRect.right));
    expect(tabRect.contains(iconRect.center + const Offset(0, -40)), isFalse);
    expect((tabRect.center - iconRect.center).distance, lessThan(200));
    expect(tabRect.overlaps(tester.getRect(find.byKey(const ValueKey('stop-pin-3')))), isFalse);
    expect(tester.widget<Text>(find.text('往 站2')).style?.fontSize, closeTo(12 * 1.3, 0.01));

    await pump(easyRead: true, textScale: 1.35);
    await tester.tap(find.byKey(const ValueKey('bus-hit-MB-HERE')));
    await tester.pump();
    final scaled = tester.getRect(find.text('即將到站'));
    final scaledTab = tester.getRect(find.byKey(const ValueKey('bus-tab-MB-HERE')));
    expect(scaledTab.inflate(1).contains(scaled.topLeft), isTrue);
    expect(scaledTab.inflate(1).contains(scaled.bottomRight), isTrue);
    expect(tester.widget<Text>(find.text('即將到站')).style?.fontSize, closeTo(12 * 1.3, 0.01));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('easy read default camera fits the route and normal mode stays close', (tester) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bus = BusController();
    bus.setRoute('3');
    bus.stopsList = [for (var i = 1; i <= 3; i++) _spreadStop(i)];
    bus.selectedStopSeq = 2;
    addTearDown(bus.dispose);

    Future<void> pump({required bool easyRead}) async {
      SharedPreferences.setMockInitialValues({'language_code': 'en'});
      final language = LanguageController();
      final location = LocationController();
      final navigation = NavigationController();
      final easy = EasyReadModeController.fixed(easyRead);
      addTearDown(language.dispose);
      addTearDown(location.dispose);
      addTearDown(navigation.dispose);
      addTearDown(easy.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<BusController>.value(value: bus),
            ChangeNotifierProvider<LanguageController>.value(value: language),
            ChangeNotifierProvider<LocationController>.value(value: location),
            ChangeNotifierProvider<NavigationController>.value(value: navigation),
            ChangeNotifierProvider<EasyReadModeController>.value(value: easy),
          ],
          child: MaterialApp(
            home: MapScreen(key: ValueKey('camera-$easyRead')),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    await pump(easyRead: false);
    expect(find.byKey(const ValueKey('stop-pin-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('stop-pin-1')), findsNothing);
    expect(find.byKey(const ValueKey('stop-pin-3')), findsNothing);

    await pump(easyRead: true);
    expect(find.byKey(const ValueKey('stop-pin-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('stop-pin-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('stop-pin-3')), findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('stop-pin-1'))).width, 26);
    expect(tester.getSize(find.byKey(const ValueKey('stop-pin-2'))).width, 32);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

bool _boxesOverlap(double icon, double tabWidth, double tabHeight, double dx, double dy) {
  final iconBox = Rect.fromCenter(center: Offset.zero, width: icon, height: icon);
  final tabBox = Rect.fromCenter(center: Offset(dx, dy), width: tabWidth, height: tabHeight);
  return iconBox.overlaps(tabBox);
}

bool _pointInTab(double x, double y, double dx, double dy, double tabWidth, double tabHeight) {
  final tabBox = Rect.fromCenter(center: Offset(dx, dy), width: tabWidth, height: tabHeight);
  return tabBox.contains(Offset(x, y));
}

Icon _coloredBusIcon(WidgetTester tester, String plate) {
  return tester.widget<Icon>(
    find.descendant(
      of: find.byKey(ValueKey('bus-hit-$plate')),
      matching: find.byWidgetPredicate(
        (widget) => widget is Icon && widget.icon == Icons.directions_bus && widget.color != Colors.white,
      ),
    ),
  );
}

Icon _chevronIcon(WidgetTester tester, String plate) {
  return tester.widget<Icon>(
    find.descendant(
      of: find.byKey(ValueKey('bus-chevron-$plate')),
      matching: find.byIcon(Icons.navigation),
    ),
  );
}

BusStop _spreadStop(int seq) {
  return BusStop(
    seq: seq,
    name: '站$seq',
    nameZh: '站$seq',
    nameZhHans: '站$seq',
    namePt: 'Paragem $seq',
    nameEn: 'Stop $seq',
    code: 'S$seq',
    lat: 22.05 + (seq - 1) * 0.12,
    lng: 113.54,
  );
}
