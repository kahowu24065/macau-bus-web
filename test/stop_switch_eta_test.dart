import 'dart:async';

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
import 'package:macau_bus_app/services/bus_api_service.dart';
import 'package:macau_bus_app/services/open_data_config.dart';
import 'package:macau_bus_app/views/screens/bus_route_screen.dart';

class _FakeSpeech implements SpeechEngine {
  String? spoken;
  int speakCount = 0;

  @override
  Future<void> prepareIos() async {}

  @override
  Future<bool> isLanguageAvailable(String language) async => true;

  @override
  Future<bool> setLanguage(String language) async => true;

  @override
  Future<List<Map<String, String>>> getVoices() async => const [];

  @override
  Future<bool> setVoice(Map<String, String> voice) async => true;

  @override
  Future<void> setSpeechRate(double rate) async {}

  @override
  Future<void> speak(String text) async {
    spoken = text;
    speakCount++;
  }
}

Bus _bus({required int seq, required int? minutes}) {
  return Bus(
    busLicense: 'MB-1',
    lat: 22.2,
    lng: 113.55,
    speed: 20,
    currentStopSeq: seq,
    etaMinutes: minutes,
  );
}

Map<String, dynamic> _eta({required int minutes, required int atSeq}) {
  return {
    'success': true,
    'etaData': {
      'status': '約 $minutes 分鐘',
      'etaMinutes': minutes,
      'busLicense': 'MB-1',
    },
    'allBuses': [_bus(seq: atSeq, minutes: minutes)],
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'language_code': 'zh'});
    OpenDataConfig.instance.debugApply(
      configRealtime: true,
      configRouteNotices: true,
      etaRealtime: true,
    );
  });

  tearDown(() {
    BusApiService.debugFetchBusETA = null;
    OpenDataConfig.instance.debugReset();
    ArrivalSpeaker.shared = ArrivalSpeaker();
  });

  testWidgets(
    'a stop switch drops the previous minutes until that stop’s fetch',
    (tester) async {
      final pending = <Completer<Map<String, dynamic>>>[];
      BusApiService.debugFetchBusETA =
          (String route, int dir, {int? targetStopSeq, String lang = 'zh'}) {
            final done = Completer<Map<String, dynamic>>();
            pending.add(done);
            return done.future;
          };

      final bus = BusController();
      try {
        bus.currentRoute = '22';
        bus.selectedStopSeq = 4;
        bus.etaData = {
          'status': '約 10 分鐘',
          'etaMinutes': 10,
          'busLicense': 'MB-1',
        };
        bus.allBusesList = [_bus(seq: 2, minutes: 10)];

        expect(bus.etaMinutesForSelectedStop, isTrue);

        bus.selectStop(4);
        expect(bus.etaData?['status'], '約 10 分鐘');
        expect(bus.allBusesList.single.etaMinutes, 10);

        final refresh = bus.fetchBusETA();
        expect(pending, hasLength(1));

        bus.selectStop(8);
        expect(bus.selectedStopSeq, 8);
        expect(bus.etaMinutesForSelectedStop, isFalse);
        expect(bus.etaData?.containsKey('status'), isFalse);
        expect(bus.etaData?.containsKey('etaMinutes'), isFalse);
        expect(bus.allBusesList.single.etaMinutes, isNull);
        expect(bus.allBusesList.single.currentStopSeq, 2);
        expect(bus.allBusesList.single.busLicense, 'MB-1');

        pending[0].complete(_eta(minutes: 10, atSeq: 2));
        await refresh;
        await tester.pump();
        expect(bus.selectedStopSeq, 8);
        expect(bus.etaMinutesForSelectedStop, isFalse);
        expect(bus.etaData?.containsKey('status'), isFalse);
        expect(bus.allBusesList.single.etaMinutes, isNull);
        expect(bus.allBusesList.single.currentStopSeq, 2);

        final next = bus.fetchBusETA();
        expect(pending, hasLength(2));
        pending[1].complete(_eta(minutes: 13, atSeq: 2));
        await next;
        await tester.pump();
        expect(bus.etaMinutesForSelectedStop, isTrue);
        expect(bus.etaData?['status'], '約 13 分鐘');
        expect(bus.allBusesList.single.etaMinutes, 13);
        expect(bus.allBusesList.single.currentStopSeq, 2);

        bus.selectStop(9);
        final failed = bus.fetchBusETA();
        expect(pending, hasLength(3));
        pending[2].complete({'success': false, 'message': 'nope'});
        await failed;
        await tester.pump();
        expect(bus.selectedStopSeq, 9);
        expect(bus.etaMinutesForSelectedStop, isFalse);
        expect(bus.etaData?.containsKey('status'), isFalse);
        expect(bus.allBusesList.single.etaMinutes, isNull);
        expect(bus.allBusesList.single.currentStopSeq, 2);
      } finally {
        bus.dispose();
      }
    },
  );

  testWidgets(
    'easy-read speech uses the selected stop’s minutes, not the previous stop',
    (tester) async {
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fake = _FakeSpeech();
      ArrivalSpeaker.shared = ArrivalSpeaker(
        engine: fake,
        isWeb: false,
        isIos: false,
      );

      final pending = <Completer<Map<String, dynamic>>>[];
      BusApiService.debugFetchBusETA =
          (String route, int dir, {int? targetStopSeq, String lang = 'zh'}) {
            final done = Completer<Map<String, dynamic>>();
            pending.add(done);
            return done.future;
          };

      final lang = LanguageController();
      final bus = BusController();
      bus.setRoute('3');
      bus.stopsList = [
        for (var i = 1; i <= 6; i++)
          BusStop(
            seq: i,
            name: '站$i',
            nameZh: '站$i',
            nameZhHans: '站$i',
            namePt: 'Paragem $i',
            nameEn: 'Stop $i',
            code: 'M$i/2',
            lat: 22.2,
            lng: 113.55,
          ),
      ];
      bus.selectedStopSeq = 3;
      bus.etaData = {'status': '約 10 分鐘', 'busLicense': 'MB-1'};
      bus.allBusesList = [_bus(seq: 1, minutes: 10)];

      try {
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<BusController>.value(value: bus),
              ChangeNotifierProvider<LanguageController>.value(value: lang),
              ChangeNotifierProvider(create: (_) => LocationController()),
              ChangeNotifierProvider(create: (_) => BackgroundController()),
              ChangeNotifierProvider(create: (_) => NavigationController()),
              ChangeNotifierProvider(
                create: (_) => EasyReadModeController.fixed(true),
              ),
            ],
            child: MaterialApp(
              theme: ThemeData.dark(),
              home: const BusRouteScreen(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('10 分鐘後到'), findsOneWidget);
        expect(fake.speakCount, 0);

        await tester.ensureVisible(find.text('站3 (M3/2)'));
        await tester.pump();
        await tester.tap(find.text('站3 (M3/2)'));
        await tester.pump();
        expect(fake.spoken, '站3，10分鐘後到啦');
        expect(fake.speakCount, 1);
        expect(pending, hasLength(1));

        await tester.ensureVisible(find.text('站6 (M6/2)'));
        await tester.pump();
        await tester.tap(find.text('站6 (M6/2)'));
        await tester.pump();

        expect(bus.selectedStopSeq, 6);
        expect(bus.etaMinutesForSelectedStop, isFalse);
        expect(find.text('10 分鐘後到'), findsNothing);
        expect(find.text('尚有 5 站'), findsOneWidget);
        expect(find.textContaining('13'), findsNothing);
        expect(fake.speakCount, 1);
        expect(fake.spoken, '站3，10分鐘後到啦');
        expect(pending, hasLength(2));

        pending[0].complete(_eta(minutes: 10, atSeq: 1));
        await tester.pump();
        await tester.pump();
        expect(find.text('10 分鐘後到'), findsNothing);
        expect(find.text('尚有 5 站'), findsOneWidget);
        expect(fake.speakCount, 1);

        pending[1].complete(_eta(minutes: 13, atSeq: 1));
        for (var i = 0; i < 8 && fake.speakCount < 2; i++) {
          await tester.pump();
        }

        expect(bus.etaMinutesForSelectedStop, isTrue);
        expect(find.text('13 分鐘後到'), findsOneWidget);
        expect(find.text('10 分鐘後到'), findsNothing);
        expect(fake.speakCount, 2);
        expect(fake.spoken, '站6，13分鐘後到啦');
        expect(fake.spoken, isNot(contains('10')));
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        bus.dispose();
        lang.dispose();
      }
    },
  );
}
