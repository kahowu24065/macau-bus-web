import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:macau_bus_app/controllers/background_controller.dart';
import 'package:macau_bus_app/controllers/bus_controller.dart';
import 'package:macau_bus_app/controllers/easy_read_mode_controller.dart';
import 'package:macau_bus_app/controllers/language_controller.dart';
import 'package:macau_bus_app/controllers/location_controller.dart';
import 'package:macau_bus_app/controllers/navigation_controller.dart';
import 'package:macau_bus_app/models/bus.dart';
import 'package:macau_bus_app/models/bus_stop.dart';
import 'package:macau_bus_app/services/arrival_speaker.dart';
import 'package:macau_bus_app/services/open_data_config.dart';
import 'package:macau_bus_app/views/screens/bus_route_screen.dart';
import 'package:macau_bus_app/views/screens/easy_read_more_screen.dart';
import 'package:macau_bus_app/views/widgets/blinking_warning_icon.dart';

class _FakeSpeech implements SpeechEngine {
  String? spoken;
  String? language;

  @override
  Future<void> prepareIos() async {}

  @override
  Future<void> setLanguage(String language) async {
    this.language = language;
  }

  @override
  Future<void> setSpeechRate(double rate) async {}

  @override
  Future<void> speak(String text) async {
    spoken = text;
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
    code: 'M$seq/2',
    lat: 22.2,
    lng: 113.55,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fake = _FakeSpeech();

  setUp(() {
    SharedPreferences.setMockInitialValues({'language_code': 'zh'});
    OpenDataConfig.instance.debugReset();
    ArrivalSpeaker.shared = ArrivalSpeaker(engine: fake, isWeb: false, isIos: false);
    fake.spoken = null;
    fake.language = null;
  });

  tearDown(() {
    OpenDataConfig.instance.debugReset();
    ArrivalSpeaker.shared = ArrivalSpeaker();
  });

  testWidgets('easy read mode shows plain arrival text and reads it aloud', (tester) async {
    OpenDataConfig.instance.debugApply(
      configRealtime: true,
      configRouteNotices: true,
      etaRealtime: true,
    );
    final lang = LanguageController();
    final bus = BusController();
    bus.setRoute('3');
    bus.stopsList = [for (var i = 1; i <= 5; i++) _stop(i)];
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

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<BusController>.value(value: bus),
          ChangeNotifierProvider<LanguageController>.value(value: lang),
          ChangeNotifierProvider(create: (_) => LocationController()),
          ChangeNotifierProvider(create: (_) => BackgroundController()),
          ChangeNotifierProvider(create: (_) => NavigationController()),
          ChangeNotifierProvider(create: (_) => EasyReadModeController.fixed(true)),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: const BusRouteScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('尚有 2 站 (約 4 分鐘)'), findsNothing);
    expect(find.text('4 分鐘後到'), findsOneWidget);
    expect(find.text('11 分鐘後到'), findsOneWidget);
    expect(find.text('更多'), findsNothing);
    expect(find.text('車資表'), findsOneWidget);
    expect(tester.widget<Text>(find.text('車資表')).style?.fontSize, 18);

    final arrival = tester.widget<Text>(find.text('4 分鐘後到'));
    expect(arrival.softWrap, isTrue);
    expect(arrival.style?.fontSize, 22);
    expect(arrival.style?.fontWeight, FontWeight.w800);

    await tester.ensureVisible(find.text('4 分鐘後到'));
    await tester.pump();
    await tester.tap(find.text('4 分鐘後到'));
    await tester.pump();
    expect(fake.spoken, '4 分鐘後到');
    expect(fake.language, 'zh-HK');

    await tester.pumpWidget(const SizedBox.shrink());
    bus.dispose();
    lang.dispose();
  });

  testWidgets('easy read warning icon opens that stop diversion page', (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    StopDetourDetailPage.debugLoad = ({
      required String route,
      required String stationCode,
      required String lang,
    }) async {
      return {
        'suspendStops': ['站$stationCode'],
        'alternativeStops': ['臨時站'],
      };
    };
    addTearDown(() => StopDetourDetailPage.debugLoad = null);

    OpenDataConfig.instance.debugApply(
      configRealtime: true,
      configRouteNotices: true,
      etaRealtime: true,
    );
    final lang = LanguageController();
    final bus = BusController();
    bus.setRoute('3');
    bus.stopsList = [
      for (var i = 1; i <= 4; i++)
        i == 2 ? _stop(i).copyWith(hasAlert: true) : _stop(i),
    ];
    bus.selectedStopSeq = 4;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<BusController>.value(value: bus),
          ChangeNotifierProvider<LanguageController>.value(value: lang),
          ChangeNotifierProvider(create: (_) => LocationController()),
          ChangeNotifierProvider(create: (_) => BackgroundController()),
          ChangeNotifierProvider(create: (_) => NavigationController()),
          ChangeNotifierProvider(create: (_) => EasyReadModeController.fixed(true)),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: const BusRouteScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final icon = find.byType(BlinkingWarningIcon);
    expect(icon, findsOneWidget);
    await tester.ensureVisible(icon);
    await tester.pump();
    await tester.tap(icon);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(StopDetourDetailPage), findsOneWidget);
    expect(find.text('暫停停靠站點：'), findsOneWidget);
    expect(find.text('臨時 / 替代站點：'), findsOneWidget);
    expect(find.text('改道通告'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    bus.dispose();
    lang.dispose();
  });
}
