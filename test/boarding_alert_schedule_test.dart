import 'package:flutter_test/flutter_test.dart';
import 'package:macau_bus_app/utils/boarding_alert_schedule.dart';

void main() {
  final now = DateTime(2026, 10, 21, 10, 51);

  test('an 8 minute arrival warns at 3 minutes and again at arrival', () {
    final arrives = now.add(const Duration(minutes: 8));
    final alerts = buildBoardingAlertNotifications(
      lang: 'zh',
      route: '102',
      stopName: '漁翁街/勞工事務局',
      endsAt: arrives.millisecondsSinceEpoch / 1000.0,
      now: now,
    );

    expect(alerts, hasLength(2));
    expect(alerts[0].id, boardingWarningNotificationId);
    expect(alerts[0].title, '102');
    expect(alerts[0].body, '預測到站尚餘約 3 分鐘');
    expect(alerts[0].at, arrives.subtract(const Duration(minutes: 3)));
    expect(alerts[1].id, boardingArrivalNotificationId);
    expect(alerts[1].body, '已到達漁翁街/勞工事務局');
    expect(alerts[1].at, arrives);
  });

  test('a millisecond endsAt is the same instant as unix seconds', () {
    final arrives = now.add(const Duration(minutes: 8));
    final plan = planBoardingAlerts(
      arrivesAt: arrivesAtFromEnds(arrives.millisecondsSinceEpoch.toDouble())!,
      now: now,
    );
    expect(plan.warningAt, arrives.subtract(const Duration(minutes: 3)));
    expect(plan.arrivalAt, arrives);
  });

  test('inside the last 3 minutes the warning says the rounded minutes left', () {
    final arrives = now.add(const Duration(seconds: 90));
    final alerts = buildBoardingAlertNotifications(
      lang: 'zh',
      route: '3A',
      stopName: 'Stop 3',
      endsAt: arrives.millisecondsSinceEpoch / 1000.0,
      now: now,
    );

    expect(alerts[0].body, '預測到站尚餘約 2 分鐘');
    expect(alerts[0].at, now.add(boardingAlertSoon));
    expect(alerts[1].body, '已到達Stop 3');
    expect(alerts[1].at, arrives);
  });

  test('a past arrival schedules nothing', () {
    final alerts = buildBoardingAlertNotifications(
      lang: 'zh',
      route: '3A',
      stopName: 'Stop 3',
      endsAt: now.subtract(const Duration(seconds: 5)).millisecondsSinceEpoch / 1000.0,
      now: now,
    );
    expect(alerts, isEmpty);
    expect(arrivesAtFromEnds(null), isNull);
    expect(arrivesAtFromEnds(0), isNull);
  });

  test('copy stays consistent in the other languages', () {
    final arrives = now.add(const Duration(minutes: 6));
    final cases = {
      'zhHans': ['上车提醒', '预测到站尚余约 3 分钟', '已到达Central'],
      'en': ['Boarding Alarm', 'About 3 minutes until predicted arrival', 'Arrived at Central'],
      'pt': ['Alarme (Embarque)', 'Cerca de 3 minutos até à chegada prevista', 'Chegou a Central'],
    };
    cases.forEach((lang, expected) {
      final alerts = buildBoardingAlertNotifications(
        lang: lang,
        route: '',
        stopName: 'Central',
        endsAt: arrives.millisecondsSinceEpoch / 1000.0,
        now: now,
      );
      expect(alerts[0].title, expected[0]);
      expect(alerts[0].body, expected[1]);
      expect(alerts[1].body, expected[2]);
    });
    expect(
      buildBoardingAlertNotifications(
        lang: 'zh',
        route: '102',
        stopName: '   ',
        endsAt: arrives.millisecondsSinceEpoch / 1000.0,
        now: now,
      )[1].body,
      '已到達',
    );
  });
}
