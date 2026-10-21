import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:macau_bus_app/controllers/bus_controller.dart';
import 'package:macau_bus_app/models/bus.dart';
import 'package:macau_bus_app/models/bus_stop.dart';
import 'package:macau_bus_app/services/boarding_reminder_client.dart';
import 'package:macau_bus_app/services/bus_api_service.dart';
import 'package:macau_bus_app/services/live_activity_bridge.dart';
import 'package:macau_bus_app/services/notification_service.dart';
import 'package:macau_bus_app/services/open_data_config.dart';
import 'package:macau_bus_app/utils/boarding_alert_schedule.dart';
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
    NotificationService.debugScheduleBoardingAlerts = (_) async {};
    NotificationService.debugCancelBoardingAlerts = () async {};
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
    NotificationService.debugScheduleBoardingAlerts = null;
    NotificationService.debugCancelBoardingAlerts = null;
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
      double? endsAt,
      String? etaLabel,
      String? arrivedText,
      String? imminentText,
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
      double? endsAt,
      String? etaLabel,
      String? arrivedText,
      String? imminentText,
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
      double? endsAt,
      String? etaLabel,
      String? arrivedText,
      String? imminentText,
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
      double? endsAt,
      String? etaLabel,
      String? arrivedText,
      String? imminentText,
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
      double? endsAt,
      String? etaLabel,
      String? arrivedText,
      String? imminentText,
    }) async {
      started.add('$stopName|$text|${etaLabel ?? ''}');
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
      expect(started.last, 'Stop 3|約 5 分鐘後到達Stop 3|預測到站時間尚餘');
    } finally {
      bus.dispose();
    }
  });

  testWidgets('boarding banners are armed from endsAt without a Live Activity token', (tester) async {
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
    LiveActivityBridge.debugStartActivity = ({
      required String route,
      required String stopName,
      required int minutes,
      required String text,
      double? endsAt,
      String? etaLabel,
      String? arrivedText,
      String? imminentText,
    }) async {
      return const LiveActivityStart(started: true);
    };
    LiveActivityBridge.debugPushToStartToken = () async => null;
    final endsAt = DateTime.now().add(const Duration(minutes: 8)).millisecondsSinceEpoch / 1000.0;
    BoardingReminderClient.debugRegister = (body) async {
      return BoardingReminderResponse(
        ok: true,
        minutes: 1,
        text: '約 1 分鐘後到達',
        startedAt: 1000,
        endDelaySeconds: 30,
        endsAt: endsAt,
      );
    };
    final scheduled = <ScheduledBoardingAlert>[];
    var cancels = 0;
    NotificationService.debugScheduleBoardingAlerts = (alerts) async {
      scheduled
        ..clear()
        ..addAll(alerts);
    };
    NotificationService.debugCancelBoardingAlerts = () async {
      cancels += 1;
      scheduled.clear();
    };

    final bus = BusController();
    try {
      await tester.pump();
      await tester.pump();
      bus.currentRoute = '102';
      bus.stopsList = [_stop(1, 0), _stop(2, 500), _stop(3, 1000)];
      bus.allBusesList = [
        Bus(busLicense: 'CLOSE', lat: _north(700), lng: _lng, speed: 20, currentStopSeq: 2),
      ];

      final outcome = await bus.setBoardingStop(3);

      expect(outcome.started, isTrue);
      expect(etaCalls, 0);
      expect(scheduled, hasLength(2));
      expect(scheduled[0].id, boardingWarningNotificationId);
      expect(scheduled[0].title, '102');
      expect(scheduled[0].body, '預測到站尚餘約 3 分鐘');
      expect(boardingArrivedLabel('zh'), '已到達');
      final warningLead = scheduled[1].at.difference(scheduled[0].at);
      expect(warningLead.inMinutes, 3);
      expect(scheduled[1].id, boardingArrivalNotificationId);
      expect(scheduled[1].body, '已到達Stop 3');
      final arrival = DateTime.fromMillisecondsSinceEpoch((endsAt * 1000).round());
      expect(scheduled[1].at.difference(arrival).inSeconds.abs(), lessThan(2));

      await bus.setBoardingStop(null);
      expect(cancels, greaterThan(0));
      expect(scheduled, isEmpty);
    } finally {
      bus.dispose();
    }
  });

  testWidgets('a passed restore drops the banners', (tester) async {
    LiveActivityBridge.debugStartActivity = ({
      required String route,
      required String stopName,
      required int minutes,
      required String text,
      double? endsAt,
      String? etaLabel,
      String? arrivedText,
      String? imminentText,
    }) async {
      return const LiveActivityStart(started: true);
    };
    LiveActivityBridge.debugPushToStartToken = () async => null;
    var posts = 0;
    BoardingReminderClient.debugRegister = (body) async {
      posts += 1;
      if (posts == 1) {
        return BoardingReminderResponse(
          ok: true,
          minutes: 8,
          text: '約 8 分鐘後到達',
          startedAt: 1000,
          endsAt: DateTime.now().add(const Duration(minutes: 8)).millisecondsSinceEpoch / 1000.0,
        );
      }
      return const BoardingReminderResponse(ok: false, code: 'passed');
    };
    final scheduled = <ScheduledBoardingAlert>[];
    var cancels = 0;
    NotificationService.debugScheduleBoardingAlerts = (alerts) async {
      scheduled
        ..clear()
        ..addAll(alerts);
    };
    NotificationService.debugCancelBoardingAlerts = () async {
      cancels += 1;
      scheduled.clear();
    };

    final bus = BusController();
    BusController? restored;
    var busDisposed = false;
    try {
      await tester.pump();
      await tester.pump();
      bus.currentRoute = '3A';
      bus.stopsList = [_stop(1, 0), _stop(2, 500), _stop(3, 1000)];
      bus.allBusesList = [
        Bus(busLicense: 'CLOSE', lat: _north(700), lng: _lng, speed: 20, currentStopSeq: 2),
      ];
      expect((await bus.setBoardingStop(3)).started, isTrue);
      expect(scheduled, hasLength(2));
      bus.dispose();
      busDisposed = true;

      restored = BusController();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      expect(posts, 1);

      restored.setRoute('3A');
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });

      expect(posts, 2);
      expect(cancels, greaterThan(0));
      expect(scheduled, isEmpty);
      expect(restored.boardingStopSeq, isNull);
    } finally {
      if (!busDisposed) bus.dispose();
      restored?.dispose();
    }
  });

  testWidgets('boarding alerts and the Live Activity use the selected language', (tester) async {
    LiveActivityBridge.debugPushToStartToken = () async => null;
    String? arrived;
    String? imminent;
    String? eta;
    LiveActivityBridge.debugStartActivity = ({
      required String route,
      required String stopName,
      required int minutes,
      required String text,
      double? endsAt,
      String? etaLabel,
      String? arrivedText,
      String? imminentText,
    }) async {
      eta = etaLabel;
      arrived = arrivedText;
      imminent = imminentText;
      return const LiveActivityStart(started: true);
    };
    BoardingReminderClient.debugRegister = (body) async {
      return BoardingReminderResponse(
        ok: true,
        minutes: 8,
        text: 'in 8 min',
        startedAt: 1000,
        endsAt: DateTime.now().add(const Duration(minutes: 8)).millisecondsSinceEpoch / 1000.0,
      );
    };
    final scheduled = <ScheduledBoardingAlert>[];
    NotificationService.debugScheduleBoardingAlerts = (alerts) async {
      scheduled
        ..clear()
        ..addAll(alerts);
    };

    final bus = BusController();
    try {
      await tester.pump();
      await tester.pump();
      bus.currentLang = 'en';
      bus.currentRoute = '102';
      bus.stopsList = [_stop(1, 0), _stop(2, 500), _stop(3, 1000)];
      bus.allBusesList = [
        Bus(busLicense: 'CLOSE', lat: _north(700), lng: _lng, speed: 20, currentStopSeq: 2),
      ];

      expect((await bus.setBoardingStop(3)).started, isTrue);
      expect(eta, 'Predicted arrival in');
      expect(arrived, 'Arrived');
      expect(imminent, 'Arriving soon');
      expect(scheduled[0].body, 'About 3 minutes until predicted arrival');
      expect(scheduled[1].body, 'Arrived at Stop 3');
    } finally {
      bus.dispose();
    }
  });

  testWidgets('the Live Activity follows the chosen bus realtime ETA', (tester) async {
    var etaCalls = 0;
    List<Bus> nextBuses = const [];
    BusApiService.debugFetchBusETA = (
      String route,
      int dir, {
      int? targetStopSeq,
      String lang = 'zh',
    }) async {
      etaCalls += 1;
      return {
        'success': true,
        'etaData': {'status': '約 1 分鐘'},
        'allBuses': nextBuses,
      };
    };
    int? startedMinutes;
    double? startedEnds;
    LiveActivityBridge.debugStartActivity = ({
      required String route,
      required String stopName,
      required int minutes,
      required String text,
      double? endsAt,
      String? etaLabel,
      String? arrivedText,
      String? imminentText,
    }) async {
      startedMinutes = minutes;
      startedEnds = endsAt;
      return const LiveActivityStart(started: true);
    };
    LiveActivityBridge.debugPushToStartToken = () async => null;
    final updates = <({int minutes, double? endsAt, String? arrived})>[];
    LiveActivityBridge.debugUpdate = ({
      required int minutes,
      required String text,
      double? endsAt,
      String? etaLabel,
      String? arrivedText,
      String? imminentText,
    }) async {
      updates.add((minutes: minutes, endsAt: endsAt, arrived: arrivedText));
    };
    final bodies = <Map<String, dynamic>>[];
    BoardingReminderClient.debugRegister = (body) async {
      bodies.add(Map<String, dynamic>.from(body));
      return const BoardingReminderResponse(
        ok: true,
        minutes: 14,
        text: '約 14 分鐘後到達',
        startedAt: 1000,
        endDelaySeconds: 14 * 60,
      );
    };
    final scheduled = <ScheduledBoardingAlert>[];
    NotificationService.debugScheduleBoardingAlerts = (alerts) async {
      scheduled
        ..clear()
        ..addAll(alerts);
    };

    Bus placed(String license, int seq, {int? eta, bool atStop = true}) {
      return Bus(
        busLicense: license,
        lat: _north(seq == 2 ? 700 : 50),
        lng: _lng,
        speed: 20,
        currentStopSeq: seq,
        atStop: atStop,
        etaMinutes: eta,
      );
    }

    final bus = BusController();
    try {
      await tester.pump();
      await tester.pump();
      bus.currentRoute = '102';
      bus.selectedStopSeq = 3;
      bus.stopsList = [_stop(1, 0), _stop(2, 500), _stop(3, 1000)];
      bus.etaData = {'status': '約 14 分鐘'};
      bus.allBusesList = [
        placed('CLOSE', 2, eta: 9),
        placed('FAR', 1, eta: 20),
      ];

      expect((await bus.setBoardingStop(3)).started, isTrue);

      expect(etaCalls, 0);
      expect(startedMinutes, 9);
      expect(startedEnds, isNotNull);
      final nineMin = DateTime.now().millisecondsSinceEpoch / 1000.0 + 9 * 60;
      expect((startedEnds! - nineMin).abs(), lessThan(5));
      expect(bodies, hasLength(1));
      expect(bodies.single['busLicense'], 'CLOSE');
      expect(bodies.single['realtimeEndsAt'], startedEnds);
      expect(scheduled, hasLength(2));
      expect(scheduled[0].body, '預測到站尚餘約 3 分鐘');
      expect(
        scheduled[1].at.difference(DateTime.now()).inSeconds,
        inInclusiveRange(8 * 60, 9 * 60 + 5),
      );

      nextBuses = [placed('CLOSE', 2, eta: 9), placed('FAR', 1, eta: 20)];
      await bus.fetchBusETA();
      expect(updates, isEmpty);
      expect(bodies, hasLength(1));

      nextBuses = [
        placed('NEAR', 2, eta: 1),
        placed('CLOSE', 1, eta: 6),
      ];
      await bus.fetchBusETA();
      expect(updates, hasLength(1));
      expect(updates.single.minutes, 6);
      expect(updates.single.arrived, '已到達');
      final sixMin = DateTime.now().millisecondsSinceEpoch / 1000.0 + 6 * 60;
      expect((updates.single.endsAt! - sixMin).abs(), lessThan(5));
      expect(bodies, hasLength(2));
      expect(bodies.last.containsKey('busLicense'), isFalse);
      expect(bodies.last['reminderId'], bodies.first['reminderId']);
      expect(((bodies.last['realtimeEndsAt'] as num) - sixMin).abs(), lessThan(5));
      expect(
        scheduled[1].at.difference(DateTime.now()).inSeconds,
        inInclusiveRange(5 * 60, 6 * 60 + 5),
      );

      bus.selectedStopSeq = 2;
      nextBuses = [placed('CLOSE', 1, eta: 2)];
      await bus.fetchBusETA();
      expect(updates, hasLength(1));

      bus.selectedStopSeq = 3;
      nextBuses = [placed('NEAR', 2, eta: 1)];
      await bus.fetchBusETA();
      expect(updates, hasLength(1));

      nextBuses = [placed('CLOSE', 3, eta: 0, atStop: true)];
      await bus.fetchBusETA();
      expect(updates, hasLength(2));
      expect(updates.last.minutes, 0);
      expect(
        updates.last.endsAt!,
        lessThanOrEqualTo(DateTime.now().millisecondsSinceEpoch / 1000.0 + 2),
      );
      expect(scheduled, hasLength(1));
      expect(scheduled.single.id, boardingArrivalNotificationId);
      expect(scheduled.single.body, '已到達Stop 3');
      expect(scheduled.single.at.difference(DateTime.now()).inSeconds, inInclusiveRange(0, 3));
      expect(etaCalls, 5);
    } finally {
      bus.stopAutoRefresh();
      bus.dispose();
    }
  });
}
