import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:macau_bus_app/controllers/background_controller.dart';
import 'package:macau_bus_app/controllers/bus_controller.dart';
import 'package:macau_bus_app/controllers/language_controller.dart';
import 'package:macau_bus_app/controllers/location_controller.dart';
import 'package:macau_bus_app/controllers/navigation_controller.dart';
import 'package:macau_bus_app/models/bus.dart';
import 'package:macau_bus_app/models/bus_stop.dart';
import 'package:macau_bus_app/services/open_data_config.dart';
import 'package:macau_bus_app/views/screens/bus_route_screen.dart';
import 'package:macau_bus_app/views/widgets/blinking_warning_icon.dart';
import 'package:macau_bus_app/views/widgets/glowing_badge.dart';

BusStop _stop({
  required int seq,
  required String zh,
  required String en,
  required String pt,
  bool hasAlert = false,
}) {
  return BusStop(
    seq: seq,
    name: zh,
    nameZh: zh,
    nameZhHans: zh,
    namePt: pt,
    nameEn: en,
    code: 'M$seq/2',
    lat: 22.2,
    lng: 113.55,
    hasAlert: hasAlert,
  );
}

Future<void> _pumpRoute(
  WidgetTester tester, {
  required BusController bus,
  required LanguageController lang,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<BusController>.value(value: bus),
        ChangeNotifierProvider<LanguageController>.value(value: lang),
        ChangeNotifierProvider(create: (_) => LocationController()),
        ChangeNotifierProvider(create: (_) => BackgroundController()),
        ChangeNotifierProvider(create: (_) => NavigationController()),
      ],
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF121212),
        ),
        home: const BusRouteScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'language_code': 'zh'});
    OpenDataConfig.instance.debugReset();
  });

  tearDown(() {
    OpenDataConfig.instance.debugReset();
  });

  testWidgets('realtime off hides ETA, buses, and detour notices', (tester) async {
    OpenDataConfig.instance.debugApply(
      configRealtime: false,
      configRouteNotices: false,
    );
    final lang = LanguageController();
    final bus = BusController();
    bus.setRoute('3');
    bus.stopsList = [
      _stop(seq: 1, zh: '關閘總站', en: 'Border Gate', pt: 'Portas do Cerco', hasAlert: true),
      _stop(seq: 2, zh: '關閘馬路', en: 'Border Gate Road', pt: 'Estrada das Portas do Cerco'),
    ];
    bus.selectedStopSeq = 1;
    bus.allBusesList = [
      const Bus(
        busLicense: 'MB-1001',
        lat: 22.2,
        lng: 113.55,
        speed: 18,
        currentStopSeq: 1,
        etaMinutes: 2,
      ),
    ];
    bus.etaData = {'status': '約 2 分鐘', 'busLicense': 'MB-1001'};

    await _pumpRoute(tester, bus: bus, lang: lang);

    expect(find.text('實時到站：申請中'), findsOneWidget);
    expect(find.text('實時動態: 以 10 至 15 秒持續更新'), findsNothing);
    expect(find.byType(LiveTrackingBadge), findsNothing);
    expect(find.textContaining('下站到達'), findsNothing);
    expect(find.textContaining('分鐘'), findsNothing);
    expect(find.textContaining('MB-1001'), findsNothing);
    expect(find.byType(BlinkingWarningIcon), findsNothing);
    expect(tester.takeException(), isNull);

    expect(tester.widget<Text>(find.text('實時到站：申請中')).softWrap, isTrue);

    await _savePng(tester, '/tmp/mbka_realtime_off_zh.png');
    await _unmount(tester, bus, lang);
  });

  testWidgets('english placeholder wraps instead of overflowing', (tester) async {
    OpenDataConfig.instance.debugApply(
      configRealtime: false,
      configRouteNotices: false,
    );
    final lang = LanguageController();
    await lang.changeLanguage('en');
    final bus = BusController();
    bus.setRoute('3');
    bus.stopsList = [
      _stop(seq: 1, zh: '關閘總站', en: 'Border Gate', pt: 'Portas do Cerco'),
    ];
    bus.selectedStopSeq = 1;
    bus.etaData = {'status': 'Real-time info not available'};

    await _pumpRoute(tester, bus: bus, lang: lang, size: const Size(320, 700));

    expect(find.text('Live arrivals: pending approval'), findsOneWidget);
    expect(find.text('Live: Updates every 10 to 15s'), findsNothing);
    expect(find.text('Real-time info not available'), findsNothing);
    expect(tester.takeException(), isNull);

    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('Live arrivals: pending approval'),
    );
    expect(tester.widget<Text>(find.text('Live arrivals: pending approval')).softWrap, isTrue);
    expect(paragraph.didExceedMaxLines, isFalse);

    await _savePng(tester, '/tmp/mbka_realtime_off_en.png');
    await _unmount(tester, bus, lang);
  });

  testWidgets('realtime on keeps the arrival lines and uses etaMinutes', (tester) async {
    OpenDataConfig.instance.debugApply(
      configRealtime: true,
      configRouteNotices: true,
      etaRealtime: true,
    );
    final lang = LanguageController();
    final bus = BusController();
    bus.setRoute('3');
    bus.stopsList = [
      for (var i = 1; i <= 5; i++)
        _stop(seq: i, zh: '站$i', en: 'Stop $i', pt: 'Paragem $i'),
    ];
    bus.selectedStopSeq = 5;
    bus.etaData = {'status': '約 4 分鐘'};
    bus.allBusesList = const [
      Bus(
        busLicense: 'MB-1',
        lat: 22.2,
        lng: 113.55,
        speed: 20,
        currentStopSeq: 3,
        etaMinutes: 4,
      ),
      Bus(
        busLicense: 'MB-2',
        lat: 22.2,
        lng: 113.55,
        speed: 20,
        currentStopSeq: 1,
        etaMinutes: 11,
      ),
    ];

    await _pumpRoute(tester, bus: bus, lang: lang);

    expect(find.text('實時到站：申請中'), findsNothing);
    expect(find.byType(LiveTrackingBadge), findsOneWidget);
    expect(find.text('尚有 2 站 (約 4 分鐘)'), findsOneWidget);
    // Scaled from the first bus this would be 8 minutes, not the server's 11.
    expect(find.text('尚有 4 站 (約 11 分鐘)'), findsOneWidget);
    expect(find.textContaining('約 8 分鐘'), findsNothing);
    expect(tester.takeException(), isNull);
    await _unmount(tester, bus, lang);
  });

  testWidgets('a one-stop bus uses its etaMinutes instead of a fixed 3', (tester) async {
    OpenDataConfig.instance.debugApply(
      configRealtime: true,
      configRouteNotices: true,
      etaRealtime: true,
    );
    final lang = LanguageController();
    final bus = BusController();
    bus.setRoute('3');
    bus.stopsList = [
      for (var i = 1; i <= 3; i++)
        _stop(seq: i, zh: '站$i', en: 'Stop $i', pt: 'Paragem $i'),
    ];
    bus.selectedStopSeq = 2;
    bus.etaData = {'status': '下一站到達', 'busLicense': 'MB-1'};
    bus.allBusesList = const [
      Bus(
        busLicense: 'MB-1',
        lat: 22.2,
        lng: 113.55,
        speed: 20,
        currentStopSeq: 1,
        etaMinutes: 1,
      ),
    ];

    await _pumpRoute(tester, bus: bus, lang: lang);

    expect(find.text('下站到達 (約 1 分鐘)'), findsOneWidget);
    expect(find.textContaining('約 3 分鐘'), findsNothing);
    expect(tester.takeException(), isNull);
    await _unmount(tester, bus, lang);
  });

  testWidgets('a one-stop bus with no eta omits the minute count', (tester) async {
    OpenDataConfig.instance.debugApply(
      configRealtime: true,
      configRouteNotices: true,
      etaRealtime: true,
    );
    final lang = LanguageController();
    final bus = BusController();
    bus.setRoute('3');
    bus.stopsList = [
      for (var i = 1; i <= 3; i++)
        _stop(seq: i, zh: '站$i', en: 'Stop $i', pt: 'Paragem $i'),
    ];
    bus.selectedStopSeq = 2;
    bus.etaData = {'status': '下一站到達'};
    bus.allBusesList = const [
      Bus(
        busLicense: 'MB-1',
        lat: 22.2,
        lng: 113.55,
        speed: 20,
        currentStopSeq: 1,
      ),
    ];

    await _pumpRoute(tester, bus: bus, lang: lang);

    expect(find.text('下站到達'), findsOneWidget);
    expect(find.textContaining('3 分鐘'), findsNothing);
    expect(find.textContaining('約 3'), findsNothing);
    expect(tester.takeException(), isNull);
    await _unmount(tester, bus, lang);
  });
}

Future<void> _unmount(WidgetTester tester, BusController bus, LanguageController lang) async {
  await tester.pumpWidget(const SizedBox.shrink());
  bus.dispose();
  lang.dispose();
}

Future<void> _savePng(WidgetTester tester, String path) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary).first,
    );
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return;
    File(path).writeAsBytesSync(bytes.buffer.asUint8List());
  });
}
