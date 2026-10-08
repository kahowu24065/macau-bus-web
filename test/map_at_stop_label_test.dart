import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:macau_bus_app/constants/app_translations.dart';
import 'package:macau_bus_app/controllers/bus_controller.dart';
import 'package:macau_bus_app/controllers/easy_read_mode_controller.dart';
import 'package:macau_bus_app/controllers/language_controller.dart';
import 'package:macau_bus_app/controllers/location_controller.dart';
import 'package:macau_bus_app/controllers/navigation_controller.dart';
import 'package:macau_bus_app/models/bus.dart';
import 'package:macau_bus_app/models/bus_stop.dart';
import 'package:macau_bus_app/services/open_data_config.dart';
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
    lat: 22.19 + seq * 0.01,
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

  testWidgets('map at-stop callout matches the station arrival text', (tester) async {
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
        lat: 22.21,
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

    Future<void> pump({required String lang, required bool easyRead}) async {
      SharedPreferences.setMockInitialValues({'language_code': lang});
      final language = LanguageController();
      addTearDown(language.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<BusController>.value(value: bus),
            ChangeNotifierProvider<LanguageController>.value(value: language),
            ChangeNotifierProvider<LocationController>.value(value: LocationController()),
            ChangeNotifierProvider<NavigationController>.value(value: NavigationController()),
            ChangeNotifierProvider<EasyReadModeController>.value(
              value: EasyReadModeController.fixed(easyRead),
            ),
          ],
          child: const MaterialApp(home: MapScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    const cases = [
      ('zh', false, '即將到站 / 到站中'),
      ('zhHans', false, '即将到站 / 到站中'),
      ('en', false, 'Arriving / At stop'),
      ('pt', false, 'A chegar / Na paragem'),
      ('zh', true, '即將到站'),
      ('zhHans', true, '即将到站'),
      ('en', true, 'Arriving soon'),
      ('pt', true, 'A chegar'),
    ];

    for (final item in cases) {
      await pump(lang: item.$1, easyRead: item.$2);
      expect(find.text('已到站'), findsNothing, reason: '${item.$1} easy=${item.$2}');
      expect(find.text(AppTranslations.data[item.$1]!['arrived_at_stop']!), findsNothing);
      final label = find.text(item.$3);
      expect(label, findsOneWidget, reason: '${item.$1} easy=${item.$2}');
      expect(tester.widget<Text>(label).style?.color, Colors.deepOrange);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Icon && widget.icon == Icons.directions_bus && widget.color == Colors.orangeAccent,
        ),
        findsWidgets,
      );
    }

    bus.allBusesList = const [
      Bus(
        busLicense: 'MB-MOVE',
        lat: 22.21,
        lng: 113.54,
        speed: 28,
        currentStopSeq: 2,
        atStop: false,
      ),
    ];
    await pump(lang: 'zh', easyRead: false);
    expect(find.text('28km/h'), findsOneWidget);
    expect(find.text('即將到站 / 到站中'), findsNothing);
    expect(find.text('已到站'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
