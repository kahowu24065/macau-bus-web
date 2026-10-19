import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:macau_bus_app/controllers/bus_controller.dart';
import 'package:macau_bus_app/models/bus.dart';
import 'package:macau_bus_app/models/bus_stop.dart';
import 'package:macau_bus_app/services/boarding_reminder_client.dart';
import 'package:macau_bus_app/services/bus_api_service.dart';
import 'package:macau_bus_app/services/live_activity_bridge.dart';
import 'package:macau_bus_app/services/open_data_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

const double _lat0 = 22.19;
const double _lng = 113.54;

double _north(double meters) => _lat0 + meters / 110540;

BusStop _stop(int seq, double meters) {
  return BusStop(
    seq: seq,
    name: 'Stop $seq',
    nameZh: 'Stop $seq',
    nameZhHans: 'Stop $seq',
    namePt: 'Stop $seq',
    nameEn: 'Stop $seq',
    code: 'S$seq',
    lat: _north(meters),
    lng: _lng,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OpenDataConfig.instance.debugApply(configRealtime: true, etaRealtime: true);
  });

  tearDown(() {
    BusApiService.debugFetchBusETA = null;
    BoardingReminderClient.debugRegister = null;
    BoardingReminderClient.debugCancel = null;
    LiveActivityBridge.debugPushToStartToken = null;
    LiveActivityBridge.debugStartActivity = null;
    LiveActivityBridge.debugUpdate = null;
    LiveActivityBridge.debugEnd = null;
    LiveActivityBridge.onActivityToken = null;
    OpenDataConfig.instance.debugReset();
  });

  testWidgets('boarding reminder posts one bus once and does not poll ETA', (tester) async {
    var etaCalls = 0;
    BusApiService.debugFetchBusETA = (
      String route,
      int dir, {
      int? targetStopSeq,
      String lang = 'zh',
    }) async {
      etaCalls += 1;
      return {'success': true, 'allBuses': <Bus>[]};
    };
    final bodies = <Map<String, dynamic>>[];
    BoardingReminderClient.debugRegister = (body) async {
      bodies.add(body);
      return const BoardingReminderResponse(
        ok: true,
        minutes: 8,
        text: '約 8 分鐘後到達',
        startedAt: 1000,
        pushConfigured: false,
      );
    };

    final bus = BusController();
    try {
      await tester.pump();
      await tester.pump();
      bus.currentRoute = '3A';
      bus.currentDirection = 0;
      bus.stopsList = [_stop(1, 0), _stop(2, 500), _stop(3, 1000)];
      bus.allBusesList = [
        Bus(
          busLicense: 'CLOSE',
          lat: _north(700),
          lng: _lng,
          speed: 20,
          currentStopSeq: 2,
        ),
        Bus(
          busLicense: 'FAR',
          lat: _north(50),
          lng: _lng,
          speed: 20,
          currentStopSeq: 1,
        ),
      ];

      final outcome = await bus.setBoardingStop(3);

      expect(outcome.started, isTrue);
      expect(outcome.messageKey, isNull);
      expect(bus.boardingStopSeq, 3);
      expect(etaCalls, 0);
      expect(bodies, hasLength(1));
      expect(bodies.single['busLicense'], 'CLOSE');
      expect(bodies.single['lat'], _north(700));
      expect(bodies.single.containsKey('stopsAway'), isFalse);
      expect(bodies.single.containsKey('stopCount'), isFalse);
      final stops = bodies.single['stops'] as List;
      expect(stops, hasLength(3));
    } finally {
      bus.dispose();
    }
  });

  testWidgets('an unusable fix uses the last coordinates from the open-route ETA', (tester) async {
    BusApiService.debugFetchBusETA = (
      String route,
      int dir, {
      int? targetStopSeq,
      String lang = 'zh',
    }) async {
      return {
        'success': true,
        'etaData': {'status': 'ok'},
        'allBuses': [
          Bus(busLicense: 'AA', lat: _north(700), lng: _lng, speed: 20, currentStopSeq: 2),
        ],
      };
    };
    Map<String, dynamic>? posted;
    BoardingReminderClient.debugRegister = (body) async {
      posted = body;
      return const BoardingReminderResponse(ok: true, minutes: 6, text: '約 6 分鐘後到達', startedAt: 5);
    };

    final bus = BusController();
    try {
      await tester.pump();
      await tester.pump();
      bus.currentRoute = '3A';
      bus.stopsList = [_stop(1, 0), _stop(2, 500), _stop(3, 1000)];
      await bus.fetchBusETA();
      bus.allBusesList = [
        const Bus(busLicense: 'AA', lat: 0, lng: 0, speed: 0, currentStopSeq: 2),
      ];

      final outcome = await bus.setBoardingStop(3);

      expect(outcome.started, isTrue);
      expect(posted?['busLicense'], 'AA');
      expect(posted?['lat'], _north(700));
      expect(posted?['lng'], _lng);
    } finally {
      bus.stopAutoRefresh();
      bus.dispose();
    }
  });

  testWidgets('no recorded position tells the user and does not start', (tester) async {
    var posts = 0;
    BoardingReminderClient.debugRegister = (body) async {
      posts += 1;
      return const BoardingReminderResponse(ok: true, minutes: 5, text: '約 5 分鐘後到達');
    };

    final bus = BusController();
    try {
      await tester.pump();
      await tester.pump();
      bus.currentRoute = '3A';
      bus.stopsList = [_stop(1, 0), _stop(2, 500), _stop(3, 1000)];
      bus.allBusesList = [
        const Bus(busLicense: 'NEAR', lat: 0, lng: 0, speed: 0, currentStopSeq: 2),
        Bus(busLicense: 'FAR', lat: _north(40), lng: _lng, speed: 20, currentStopSeq: 1),
      ];

      final outcome = await bus.setBoardingStop(3);

      expect(outcome.started, isFalse);
      expect(outcome.messageKey, 'boarding_no_position');
      expect(bus.boardingStopSeq, isNull);
      expect(posts, 0);
    } finally {
      bus.dispose();
    }
  });

  testWidgets('a live activity token that never arrives still posts and marks the stop', (tester) async {
    final hung = Completer<String?>();
    LiveActivityBridge.debugPushToStartToken = () => hung.future;
    LiveActivityBridge.debugStartActivity = ({
      required String route,
      required String stopName,
      required int minutes,
      required String text,
    }) async {
      return const LiveActivityStart(started: true);
    };
    final bodies = <Map<String, dynamic>>[];
    BoardingReminderClient.debugRegister = (body) async {
      bodies.add(Map<String, dynamic>.from(body));
      return const BoardingReminderResponse(
        ok: true,
        minutes: 5,
        text: '約 5 分鐘後到達',
        startedAt: 1000,
      );
    };

    final bus = BusController();
    try {
      await tester.pump();
      await tester.pump();
      bus.currentRoute = '3A';
      bus.currentDirection = 0;
      bus.stopsList = [_stop(1, 0), _stop(2, 500), _stop(3, 1000)];
      bus.allBusesList = [
        Bus(busLicense: 'CLOSE', lat: _north(700), lng: _lng, speed: 20, currentStopSeq: 2),
      ];

      final outcome = await bus.setBoardingStop(3).timeout(const Duration(seconds: 2));

      expect(outcome.started, isTrue);
      expect(outcome.messageKey, isNull);
      expect(bus.boardingStopSeq, 3);
      expect(bodies, hasLength(1));
      expect(bodies.single.containsKey('pushToStartToken'), isFalse);
      expect(bodies.single.containsKey('activityToken'), isFalse);
      expect(bodies.single['stops'], isA<List>());
    } finally {
      if (!hung.isCompleted) hung.complete(null);
      await tester.pump();
      bus.dispose();
    }
  });

  testWidgets('a live activity token is posted on the follow-up register', (tester) async {
    LiveActivityBridge.debugStartActivity = ({
      required String route,
      required String stopName,
      required int minutes,
      required String text,
    }) async {
      return const LiveActivityStart(started: true, token: 'abc123hex');
    };
    LiveActivityBridge.debugPushToStartToken = () async => null;
    final bodies = <Map<String, dynamic>>[];
    BoardingReminderClient.debugRegister = (body) async {
      bodies.add(Map<String, dynamic>.from(body));
      return const BoardingReminderResponse(
        ok: true,
        minutes: 5,
        text: '約 5 分鐘後到達',
        startedAt: 1000,
      );
    };

    final bus = BusController();
    try {
      await tester.pump();
      await tester.pump();
      bus.currentRoute = '3A';
      bus.currentDirection = 0;
      bus.stopsList = [_stop(1, 0), _stop(2, 500), _stop(3, 1000)];
      bus.allBusesList = [
        Bus(busLicense: 'CLOSE', lat: _north(700), lng: _lng, speed: 20, currentStopSeq: 2),
      ];

      final outcome = await bus.setBoardingStop(3);
      expect(outcome.started, isTrue);
      await tester.pump();

      expect(bodies.first.containsKey('activityToken'), isFalse);
      expect(bodies.any((body) => body['activityToken'] == 'abc123hex'), isTrue);
      expect(bodies.last['reminderId'], bodies.first['reminderId']);
    } finally {
      bus.dispose();
    }
  });

  testWidgets('a Live Activity start failure still marks the stop and says why', (tester) async {
    LiveActivityBridge.debugStartActivity = ({
      required String route,
      required String stopName,
      required int minutes,
      required String text,
    }) async {
      return const LiveActivityStart(started: false, error: 'activities_disabled');
    };
    LiveActivityBridge.debugPushToStartToken = () async => null;
    final bodies = <Map<String, dynamic>>[];
    BoardingReminderClient.debugRegister = (body) async {
      bodies.add(Map<String, dynamic>.from(body));
      return const BoardingReminderResponse(
        ok: true,
        minutes: 5,
        text: '約 5 分鐘後到達',
        startedAt: 1000,
      );
    };

    final bus = BusController();
    try {
      await tester.pump();
      await tester.pump();
      bus.currentRoute = '3A';
      bus.currentDirection = 0;
      bus.stopsList = [_stop(1, 0), _stop(2, 500), _stop(3, 1000)];
      bus.allBusesList = [
        Bus(busLicense: 'CLOSE', lat: _north(700), lng: _lng, speed: 20, currentStopSeq: 2),
      ];

      final outcome = await bus.setBoardingStop(3);

      expect(outcome.started, isTrue);
      expect(outcome.messageKey, 'boarding_live_disabled');
      expect(outcome.detail, 'activities_disabled');
      expect(bus.boardingStopSeq, 3);
      expect(bodies, hasLength(1));
      expect(bodies.single.containsKey('activityToken'), isFalse);
    } finally {
      bus.dispose();
    }
  });

  testWidgets('a token that arrives after start is posted on the follow-up register', (tester) async {
    LiveActivityBridge.debugStartActivity = ({
      required String route,
      required String stopName,
      required int minutes,
      required String text,
    }) async {
      return const LiveActivityStart(started: true);
    };
    LiveActivityBridge.debugPushToStartToken = () async => null;
    final bodies = <Map<String, dynamic>>[];
    BoardingReminderClient.debugRegister = (body) async {
      bodies.add(Map<String, dynamic>.from(body));
      return const BoardingReminderResponse(
        ok: true,
        minutes: 5,
        text: '約 5 分鐘後到達',
        startedAt: 1000,
      );
    };

    final bus = BusController();
    try {
      await tester.pump();
      await tester.pump();
      bus.currentRoute = '3A';
      bus.currentDirection = 0;
      bus.stopsList = [_stop(1, 0), _stop(2, 500), _stop(3, 1000)];
      bus.allBusesList = [
        Bus(busLicense: 'CLOSE', lat: _north(700), lng: _lng, speed: 20, currentStopSeq: 2),
      ];

      final outcome = await bus.setBoardingStop(3);
      expect(outcome.started, isTrue);
      expect(outcome.messageKey, isNull);
      LiveActivityBridge.onActivityToken?.call('latehex');
      await tester.pump();
      await tester.pump();

      expect(bodies.first.containsKey('activityToken'), isFalse);
      expect(bodies.any((body) => body['activityToken'] == 'latehex'), isTrue);
      expect(bodies.last['reminderId'], bodies.first['reminderId']);
    } finally {
      bus.dispose();
    }
  });

  testWidgets('a new stop ends the previous Live Activity and cancels that reminder', (tester) async {
    final cancelled = <String>[];
    var ends = 0;
    final started = <String>[];
    BoardingReminderClient.debugCancel = (id) async {
      cancelled.add(id);
    };
    LiveActivityBridge.debugEnd = () async {
      ends += 1;
    };
    LiveActivityBridge.debugStartActivity = ({
      required String route,
      required String stopName,
      required int minutes,
      required String text,
    }) async {
      started.add('$stopName|$text');
      return const LiveActivityStart(started: true);
    };
    LiveActivityBridge.debugPushToStartToken = () async => null;
    final bodies = <Map<String, dynamic>>[];
    BoardingReminderClient.debugRegister = (body) async {
      bodies.add(Map<String, dynamic>.from(body));
      final stopName = body['stopName'] ?? '';
      return BoardingReminderResponse(
        ok: true,
        minutes: 5,
        text: '約 5 分鐘後到達$stopName',
        startedAt: 1000,
      );
    };

    final bus = BusController();
    try {
      await tester.pump();
      await tester.pump();
      bus.currentRoute = '3A';
      bus.stopsList = [_stop(1, 0), _stop(2, 500), _stop(3, 1000)];
      bus.allBusesList = [
        Bus(busLicense: 'CLOSE', lat: _north(50), lng: _lng, speed: 20, currentStopSeq: 1),
      ];

      final first = await bus.setBoardingStop(2);
      expect(first.started, isTrue);
      expect(cancelled, isEmpty);
      expect(ends, 0);
      final firstId = bodies.single['reminderId'] as String;

      final second = await bus.setBoardingStop(3);
      expect(second.started, isTrue);
      expect(bus.boardingStopSeq, 3);
      expect(cancelled, [firstId]);
      expect(ends, 1);
      expect(bodies.last['reminderId'], isNot(firstId));
      expect(bodies.last['targetSeq'], 3);
      expect(started.last, 'Stop 3|約 5 分鐘後到達Stop 3');
    } finally {
      bus.dispose();
    }
  });
}
