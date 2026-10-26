import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:macau_bus_app/controllers/bus_controller.dart';
import 'package:macau_bus_app/models/bus.dart';
import 'package:macau_bus_app/models/bus_stop.dart';
import 'package:macau_bus_app/services/open_data_config.dart';
import 'package:macau_bus_app/utils/map_segment_reference.dart';

BusStop _stop(int seq, double lat, {double lng = 113.54}) {
  return BusStop(
    seq: seq,
    name: '站$seq',
    nameZh: '站$seq',
    nameZhHans: '站$seq',
    namePt: 'Paragem $seq',
    nameEn: 'Stop $seq',
    code: 'M$seq',
    lat: lat,
    lng: lng,
  );
}

Bus _bus({
  required double lat,
  required double speed,
  required int seq,
  double lng = 113.54,
  bool atStop = false,
  String plate = 'MB-1',
  int? etaMinutes,
}) {
  return Bus(
    busLicense: plate,
    lat: lat,
    lng: lng,
    speed: speed,
    currentStopSeq: seq,
    atStop: atStop,
    etaMinutes: etaMinutes,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const distance = Distance();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OpenDataConfig.instance.debugApply(configRealtime: true, etaRealtime: true);
  });

  tearDown(() {
    OpenDataConfig.instance.debugReset();
  });

  BusController route() {
    final bus = BusController();
    bus.stopsList = [
      _stop(1, 22.19),
      _stop(2, 22.20),
      _stop(3, 22.21),
    ];
    return bus;
  }

  double apart(LatLng a, LatLng b) => distance.as(LengthUnit.Meter, a, b);

  /// Metres added by damped dead-reckoning, ignoring the 1s ease onto a new fix.
  double predictedExtra(double speedKmh, double ageSeconds) {
    final predict = ageSeconds < 0 ? 0.0 : ageSeconds;
    final horizon = BusController.mapPredictHorizonSeconds;
    final full = predict > horizon ? horizon : predict;
    var coast = predict - horizon;
    if (coast < 0) coast = 0;
    if (coast > BusController.mapCoastSeconds) coast = BusController.mapCoastSeconds;
    final extra = speedKmh /
        3.6 *
        (full * BusController.mapPredictSpeedFactor + coast * BusController.mapCoastSpeedFactor);
    return math.min(extra, BusController.mapPredictMaxMeters);
  }

  void expectMoved(double actual, double expected) {
    final slack = math.max(1.5, expected * 0.12);
    expect(
      actual,
      inInclusiveRange(expected - slack, expected + slack),
      reason: 'moved ${actual.toStringAsFixed(1)}m, expected about ${expected.toStringAsFixed(1)}m',
    );
  }

  test('fresh GPS is placed on the route, and a stopped bus stays there', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    const halfway = LatLng(22.195, 113.54);
    bus.allBusesList = [_bus(lat: halfway.latitude, speed: 0, seq: 1)];

    bus.advanceBusMotion(t0);
    final placed = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(placed, halfway), lessThan(25));
    expect(apart(placed, const LatLng(22.19, 113.54)), greaterThan(400));
    expect(bus.displaySpeedKmh(bus.allBusesList.single), 0);

    bus.advanceBusMotion(t0.add(const Duration(seconds: 4)));
    final held = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(held, placed), lessThan(1));
    expect(bus.displaySpeedKmh(bus.allBusesList.single), 0);
  });

  test('speed at or below 5 km/h is stopped, including the displayed speed', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.195, speed: 5, seq: 1)];
    bus.advanceBusMotion(t0);
    final placed = bus.snapBusToStop(bus.allBusesList.single)!;
    bus.advanceBusMotion(t0.add(const Duration(seconds: 4)));
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, placed), lessThan(1));
    expect(bus.displaySpeedKmh(bus.allBusesList.single), 0);
  });

  test('speed just above 5 km/h creeps, coasts, then holds short of full speed', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.195, speed: 6, seq: 1)];
    bus.advanceBusMotion(t0);
    final atFix = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(bus.displaySpeedKmh(bus.allBusesList.single), 6);

    bus.advanceBusMotion(t0.add(const Duration(seconds: 2)));
    final early = bus.snapBusToStop(bus.allBusesList.single)!;
    expectMoved(apart(early, atFix), predictedExtra(6, 2));

    bus.advanceBusMotion(t0.add(const Duration(seconds: 8)));
    final coasting = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(coasting, early), greaterThan(0.4));

    final fullTen = 6 / 3.6 * 10;
    bus.advanceBusMotion(t0.add(const Duration(seconds: 10)));
    final atPoll = bus.snapBusToStop(bus.allBusesList.single)!;
    expectMoved(apart(atPoll, atFix), predictedExtra(6, 10));
    expect(apart(atPoll, atFix), lessThan(fullTen * 0.7));

    final holdAt = BusController.mapPredictHorizonSeconds + BusController.mapCoastSeconds;
    bus.advanceBusMotion(t0.add(Duration(milliseconds: (holdAt * 1000).round())));
    final held = bus.snapBusToStop(bus.allBusesList.single)!;
    bus.advanceBusMotion(t0.add(Duration(milliseconds: (holdAt * 1000).round() + 4000)));
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, held), lessThan(1));
  });

  test('a later speed of 0 does not keep sliding at the previous speed', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.195, speed: 36, seq: 1)];
    bus.advanceBusMotion(t0);
    final atFix = bus.snapBusToStop(bus.allBusesList.single)!;
    bus.advanceBusMotion(t0.add(const Duration(seconds: 2)));
    final ahead = bus.snapBusToStop(bus.allBusesList.single)!;
    expectMoved(apart(ahead, atFix), predictedExtra(36, 2));
    bus.advanceBusMotion(t0.add(const Duration(seconds: 4)));
    final later = bus.snapBusToStop(bus.allBusesList.single)!;
    expectMoved(apart(later, ahead), predictedExtra(36, 4) - predictedExtra(36, 2));

    bus.allBusesList = [_bus(lat: 22.196, speed: 0, seq: 1)];
    final stoppedAt = t0.add(const Duration(seconds: 4));
    bus.advanceBusMotion(stoppedAt);
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, later), lessThan(5));

    bus.advanceBusMotion(stoppedAt.add(const Duration(seconds: 1)));
    final parked = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(parked, const LatLng(22.196, 113.54)), lessThan(25));
    bus.advanceBusMotion(stoppedAt.add(const Duration(seconds: 5)));
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, parked), lessThan(1));
    expect(bus.displaySpeedKmh(bus.allBusesList.single), 0);
  });

  test('moving buses dead-reckon slower than reported speed, then coast', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.195, speed: 30, seq: 1)];
    bus.advanceBusMotion(t0);
    final atFix = bus.snapBusToStop(bus.allBusesList.single)!;

    bus.advanceBusMotion(t0.add(const Duration(seconds: 1)));
    final early = bus.snapBusToStop(bus.allBusesList.single)!;
    expectMoved(apart(early, atFix), predictedExtra(30, 1));

    bus.advanceBusMotion(t0.add(const Duration(seconds: 4)));
    final mid = bus.snapBusToStop(bus.allBusesList.single)!;
    expectMoved(apart(mid, atFix), predictedExtra(30, 4));
    expect(apart(mid, early), greaterThan(8));

    bus.advanceBusMotion(t0.add(const Duration(seconds: 10)));
    final atPoll = bus.snapBusToStop(bus.allBusesList.single)!;
    expectMoved(apart(atPoll, atFix), predictedExtra(30, 10));
    expect(apart(atPoll, atFix), lessThan(30 / 3.6 * 10 * 0.6));

    bus.advanceBusMotion(t0.add(const Duration(seconds: 14)));
    final stillCoasting = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(stillCoasting, atPoll), greaterThan(4));
    expect(bus.displaySpeedKmh(bus.allBusesList.single), 30);

    final holdAt = BusController.mapPredictHorizonSeconds + BusController.mapCoastSeconds;
    bus.advanceBusMotion(t0.add(Duration(milliseconds: (holdAt * 1000).round())));
    final held = bus.snapBusToStop(bus.allBusesList.single)!;
    bus.advanceBusMotion(t0.add(Duration(milliseconds: (holdAt * 1000).round() + 4000)));
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, held), lessThan(1));
  });

  test('a new fix eases onto the GPS point over a second before using speed', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.192, speed: 30, seq: 1)];
    bus.advanceBusMotion(t0);
    bus.advanceBusMotion(t0.add(const Duration(seconds: 2)));
    final before = bus.snapBusToStop(bus.allBusesList.single)!;

    const nextFix = LatLng(22.196, 113.54);
    final fixAt = t0.add(const Duration(seconds: 2));
    bus.allBusesList = [_bus(lat: nextFix.latitude, speed: 30, seq: 1)];
    bus.advanceBusMotion(fixAt);
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, before), lessThan(5));

    bus.advanceBusMotion(fixAt.add(const Duration(milliseconds: 500)));
    final mid = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(mid, before), greaterThan(40));
    expect(apart(mid, nextFix), greaterThan(40));
    expect(apart(mid, before) + apart(mid, nextFix), closeTo(apart(before, nextFix), 30));

    bus.advanceBusMotion(fixAt.add(const Duration(seconds: 1)));
    final eased = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(eased, nextFix), lessThan(25));

    bus.advanceBusMotion(fixAt.add(const Duration(seconds: 2)));
    final after = bus.snapBusToStop(bus.allBusesList.single)!;
    expectMoved(apart(after, eased), predictedExtra(30, 1));
    bus.advanceBusMotion(fixAt.add(const Duration(seconds: 4)));
    final later = bus.snapBusToStop(bus.allBusesList.single)!;
    expectMoved(apart(later, after), predictedExtra(30, 3) - predictedExtra(30, 1));
    bus.advanceBusMotion(fixAt.add(const Duration(seconds: 12)));
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, later), greaterThan(10));
  });

  test('a new stop sequence keeps the GPS position instead of snapping to the stop', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.199, speed: 18, seq: 1)];
    bus.advanceBusMotion(t0);
    final before = bus.snapBusToStop(bus.allBusesList.single)!;

    const gps = LatLng(22.205, 113.54);
    final changed = t0.add(const Duration(seconds: 2));
    bus.allBusesList = [_bus(lat: gps.latitude, speed: 18, seq: 2)];
    bus.advanceBusMotion(changed);
    final atChange = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(atChange, before), lessThan(20));
    expect(apart(atChange, const LatLng(22.20, 113.54)), greaterThan(20));

    bus.advanceBusMotion(changed.add(const Duration(seconds: 1)));
    final eased = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(eased, gps), lessThan(25));
    expect(apart(eased, const LatLng(22.20, 113.54)), greaterThan(400));
  });

  test('speed cannot carry the icon past the next stop before that stop is current', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    const stop2 = LatLng(22.20, 113.54);
    bus.allBusesList = [_bus(lat: 22.1995, speed: 80, seq: 1)];
    for (var second = 0; second <= 12; second++) {
      bus.advanceBusMotion(t0.add(Duration(seconds: second)));
    }
    final icon = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(icon, stop2), greaterThan(20));
  });

  test('a stopped terminal leg stays on its GPS fix and does not creep at 20 km/h', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    const halfway = LatLng(22.205, 113.54);
    const terminal = LatLng(22.21, 113.54);
    bus.allBusesList = [
      _bus(lat: halfway.latitude, speed: 0, seq: 3, atStop: true),
    ];
    bus.advanceBusMotion(t0);
    expect(bus.hasVisuallyArrived(bus.allBusesList.single), isFalse);
    bus.advanceBusMotion(t0.add(const Duration(seconds: 8)));
    final icon = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(icon, halfway), lessThan(25));
    expect(apart(icon, terminal), greaterThan(400));
    expect(bus.hasVisuallyArrived(bus.allBusesList.single), isFalse);
    expect(bus.displaySpeedKmh(bus.allBusesList.single), 0);
  });

  test('a moving terminal leg can still reach the stop', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [
      _bus(lat: 22.20982, speed: 50, seq: 3, atStop: true),
    ];
    bus.advanceBusMotion(t0);
    expect(bus.hasVisuallyArrived(bus.allBusesList.single), isFalse);
    bus.advanceBusMotion(t0.add(const Duration(seconds: 4)));
    expect(bus.hasVisuallyArrived(bus.allBusesList.single), isTrue);
    expect(bus.displaySpeedKmh(bus.allBusesList.single), 50);
  });

  test('a GPS on a long route segment stays on the line instead of a stop vertex', () {
    final bus = route();
    addTearDown(bus.dispose);
    bus.gpxRoutePoints = const [
      LatLng(22.19, 113.54),
      LatLng(22.20, 113.54),
    ];
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.195, speed: 0, seq: 1)];
    bus.advanceBusMotion(t0);
    final placed = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(placed, const LatLng(22.195, 113.54)), lessThan(25));
    expect(apart(placed, const LatLng(22.19, 113.54)), greaterThan(400));
    expect(apart(placed, const LatLng(22.20, 113.54)), greaterThan(400));
  });

  test('dead reckoning follows a bent route instead of the stop-to-stop chord', () {
    final bus = route();
    addTearDown(bus.dispose);
    bus.stopsList = [
      _stop(1, 22.19),
      _stop(2, 22.20),
    ];
    bus.gpxRoutePoints = const [
      LatLng(22.19, 113.54),
      LatLng(22.195, 113.545),
      LatLng(22.20, 113.54),
    ];
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.19, speed: 30, seq: 1)];
    bus.advanceBusMotion(t0);
    bus.advanceBusMotion(t0.add(const Duration(seconds: 10)));
    final icon = bus.snapBusToStop(bus.allBusesList.single)!;
    // Damped 10s of 30 km/h stays on the first leg of the bend, east of the
    // stop-to-stop chord (which keeps longitude 113.54).
    expect(icon.longitude, greaterThan(113.54012));
    expect(icon.longitude, lessThan(113.545));
    expect(apart(icon, const LatLng(22.19, 113.54)), greaterThan(25));
  });

  test('short samples keep the reported speed instead of hopping', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.195, speed: 36, seq: 1)];
    bus.advanceBusMotion(t0);
    expect(bus.displaySpeedKmh(bus.allBusesList.single), 36);
    var previous = bus.snapBusToStop(bus.allBusesList.single)!;
    final origin = previous;
    for (var step = 1; step <= 10; step++) {
      bus.advanceBusMotion(t0.add(Duration(milliseconds: 100 * step)));
      final here = bus.snapBusToStop(bus.allBusesList.single)!;
      final moved = const Distance(roundResult: false).as(LengthUnit.Meter, here, previous);
      final stepMeters = predictedExtra(36, 0.1);
      expect(moved, greaterThan(stepMeters * 0.75));
      expect(moved, lessThan(stepMeters * 1.25));
      previous = here;
    }
    expectMoved(
      const Distance(roundResult: false).as(LengthUnit.Meter, previous, origin),
      predictedExtra(36, 1),
    );
    expect(bus.displaySpeedKmh(bus.allBusesList.single), 36);
    expect(BusController.mapMotionFrame.inMilliseconds, inInclusiveRange(16, 40));
  });

  test('a same-leg correction eases along the bend instead of cutting the corner', () {
    final bus = route();
    addTearDown(bus.dispose);
    const corner = LatLng(22.19072, 113.54);
    const end = LatLng(22.19072, 113.54078);
    bus.stopsList = [
      _stop(1, 22.19),
      _stop(2, end.latitude, lng: end.longitude),
    ];
    bus.gpxRoutePoints = const [
      LatLng(22.19, 113.54),
      corner,
      end,
    ];
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.19, speed: 18, seq: 1)];
    bus.advanceBusMotion(t0);
    final fixAt = t0.add(const Duration(seconds: 2));
    bus.advanceBusMotion(fixAt);
    final before = bus.snapBusToStop(bus.allBusesList.single)!;

    bus.allBusesList = [_bus(lat: end.latitude, lng: end.longitude, speed: 18, seq: 1)];
    bus.advanceBusMotion(fixAt);
    bus.advanceBusMotion(fixAt.add(const Duration(milliseconds: 500)));
    final mid = bus.snapBusToStop(bus.allBusesList.single)!;
    final chord = LatLng(
      (before.latitude + end.latitude) / 2,
      (before.longitude + end.longitude) / 2,
    );
    // The bend goes north first. A straight ease is still south of the corner
    // at the halfway mark; the route ease is already up at the corner.
    expect(mid.latitude, greaterThan(chord.latitude + 0.0001), reason: 'before=$before mid=$mid chord=$chord');
    expect(apart(mid, corner), lessThan(apart(chord, corner)));
  });

  test('without motion yet, the icon still follows GPS instead of the last stop', () {
    final bus = route();
    addTearDown(bus.dispose);
    bus.allBusesList = [_bus(lat: 22.195, speed: 12, seq: 1)];
    final icon = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(icon, const LatLng(22.195, 113.54)), lessThan(25));
    expect(apart(icon, const LatLng(22.19, 113.54)), greaterThan(400));
  });

  test('a fix behind the icon does not pull it backward', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.195, speed: 36, seq: 1)];
    bus.advanceBusMotion(t0);
    bus.advanceBusMotion(t0.add(const Duration(seconds: 4)));
    final ahead = bus.snapBusToStop(bus.allBusesList.single)!;

    final backAt = t0.add(const Duration(seconds: 4));
    bus.allBusesList = [_bus(lat: 22.192, speed: 36, seq: 1)];
    bus.advanceBusMotion(backAt);
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, ahead), lessThan(5));

    bus.advanceBusMotion(backAt.add(const Duration(seconds: 3)));
    final held = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(held, ahead), lessThan(5));
    expect(held.latitude, greaterThan(22.192));
  });

  test('atStop on the current stop does not snap the icon backward', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.195, speed: 36, seq: 1)];
    bus.advanceBusMotion(t0);
    bus.advanceBusMotion(t0.add(const Duration(seconds: 4)));
    final ahead = bus.snapBusToStop(bus.allBusesList.single)!;

    bus.allBusesList = [_bus(lat: 22.19, speed: 0, seq: 1, atStop: true)];
    bus.advanceBusMotion(t0.add(const Duration(seconds: 4)));
    final held = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(held, ahead), lessThan(5));
    expect(apart(held, const LatLng(22.19, 113.54)), greaterThan(20));
    expect(bus.hasVisuallyArrived(bus.allBusesList.single), isFalse);
  });

  test('one stop-sequence retreat does not jump the icon backward', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.201, speed: 0, seq: 2)];
    bus.advanceBusMotion(t0);
    final placed = bus.snapBusToStop(bus.allBusesList.single)!;

    bus.allBusesList = [_bus(lat: 22.192, speed: 20, seq: 1)];
    bus.advanceBusMotion(t0);
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, placed), lessThan(8));
    bus.advanceBusMotion(t0.add(const Duration(seconds: 5)));
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, placed), lessThan(8));
  });

  test('a second distinct stop retreat places the new trip', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.201, speed: 0, seq: 2)];
    bus.advanceBusMotion(t0);
    final placed = bus.snapBusToStop(bus.allBusesList.single)!;

    bus.allBusesList = [_bus(lat: 22.192, speed: 0, seq: 1)];
    bus.advanceBusMotion(t0);
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, placed), lessThan(8));

    bus.allBusesList = [_bus(lat: 22.193, speed: 0, seq: 1)];
    bus.advanceBusMotion(t0.add(const Duration(seconds: 1)));
    final reset = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(reset, const LatLng(22.193, 113.54)), lessThan(25));
    expect(apart(reset, placed), greaterThan(100));
  });

  test('a stop retreat that stays for two polls resets the floor', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.201, speed: 0, seq: 2)];
    bus.advanceBusMotion(t0);
    final placed = bus.snapBusToStop(bus.allBusesList.single)!;

    final seen = t0.add(const Duration(seconds: 1));
    bus.allBusesList = [_bus(lat: 22.191, speed: 0, seq: 1)];
    bus.advanceBusMotion(seen);
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, placed), lessThan(8));

    bus.advanceBusMotion(seen.add(BusController.mapTripResetHold - const Duration(seconds: 1)));
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, placed), lessThan(8));

    bus.advanceBusMotion(seen.add(BusController.mapTripResetHold));
    final reset = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(reset, const LatLng(22.191, 113.54)), lessThan(25));
    expect(apart(reset, placed), greaterThan(100));
  });

  test('a bus that leaves the list can be placed behind on the way back', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.195, speed: 36, seq: 1)];
    bus.advanceBusMotion(t0);
    bus.advanceBusMotion(t0.add(const Duration(seconds: 4)));
    final ahead = bus.snapBusToStop(bus.allBusesList.single)!;

    bus.allBusesList = [];
    bus.advanceBusMotion(t0.add(const Duration(seconds: 5)));
    bus.allBusesList = [_bus(lat: 22.191, speed: 0, seq: 1)];
    bus.advanceBusMotion(t0.add(const Duration(seconds: 6)));
    final again = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(again, const LatLng(22.191, 113.54)), lessThan(25));
    expect(apart(again, ahead), greaterThan(100));
  });

  test('a fix ahead of the icon still eases forward after a rejected one', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.195, speed: 30, seq: 1)];
    bus.advanceBusMotion(t0);
    bus.advanceBusMotion(t0.add(const Duration(seconds: 3)));
    final ahead = bus.snapBusToStop(bus.allBusesList.single)!;

    final rejectedAt = t0.add(const Duration(seconds: 3));
    bus.allBusesList = [_bus(lat: 22.194, speed: 30, seq: 1)];
    bus.advanceBusMotion(rejectedAt);
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, ahead), lessThan(5));

    const nextFix = LatLng(22.198, 113.54);
    final fixAt = rejectedAt.add(const Duration(seconds: 2));
    bus.allBusesList = [_bus(lat: nextFix.latitude, speed: 30, seq: 1)];
    bus.advanceBusMotion(fixAt);
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, ahead), lessThan(8));
    bus.advanceBusMotion(fixAt.add(const Duration(seconds: 1)));
    final eased = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(eased, nextFix), lessThan(30));
    expect(eased.latitude, greaterThan(ahead.latitude));
  });

  test('ETA to the next stop slows a fast snapshot', () {
    final bus = route();
    addTearDown(bus.dispose);
    bus.selectStop(2);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    const fix = LatLng(22.195, 113.54);
    const from = LatLng(22.19, 113.54);
    const to = LatLng(22.20, 113.54);
    final length = distance.as(LengthUnit.Meter, from, to);
    final gps = distance.as(LengthUnit.Meter, from, fix);
    final gap = length - gps;
    bus.allBusesList = [_bus(lat: fix.latitude, speed: 36, seq: 1, etaMinutes: 8)];
    bus.advanceBusMotion(t0);
    final atFix = bus.snapBusToStop(bus.allBusesList.single)!;
    bus.advanceBusMotion(t0.add(const Duration(seconds: 10)));
    final moved = apart(bus.snapBusToStop(bus.allBusesList.single)!, atFix);
    final speedOnly = predictedExtra(36, 10);
    final paced = gap / (8 * 60) * 10;
    final blended = speedOnly * (1 - BusController.mapEtaBlend) + paced * BusController.mapEtaBlend;
    expect(paced, lessThan(speedOnly));
    expectMoved(moved, blended);
    expect(moved, lessThan(speedOnly * 0.85));
  });

  test('a stopped bus still eases forward while ETA has time left', () {
    final bus = route();
    addTearDown(bus.dispose);
    bus.selectStop(2);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    const fix = LatLng(22.195, 113.54);
    const from = LatLng(22.19, 113.54);
    const to = LatLng(22.20, 113.54);
    final gap = distance.as(LengthUnit.Meter, from, to) - distance.as(LengthUnit.Meter, from, fix);
    bus.allBusesList = [_bus(lat: fix.latitude, speed: 0, seq: 1, etaMinutes: 2)];
    bus.advanceBusMotion(t0);
    final atFix = bus.snapBusToStop(bus.allBusesList.single)!;
    bus.advanceBusMotion(t0.add(const Duration(seconds: 10)));
    final moved = apart(bus.snapBusToStop(bus.allBusesList.single)!, atFix);
    final paced = gap / (2 * 60) * 10 * BusController.mapEtaBlend;
    expectMoved(moved, paced);
    expect(moved, greaterThan(15));
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, to), greaterThan(80));
    expect(bus.displaySpeedKmh(bus.allBusesList.single), 0);
  });

  test('ETA covering a later stop only spends this leg its share of the time', () {
    final current = etaRemainingOnLeg(
      etaMinutes: 8,
      gpsMeters: 500,
      hops: const [
        MapLegHop(fromSeq: 1, toSeq: 2, meters: 1000),
        MapLegHop(fromSeq: 2, toSeq: 3, meters: 1000),
      ],
    );
    // Half of this hop remains, plus the next hop: 500 / 1500 of 8 minutes.
    expect(current, closeTo(8 * 60 * (500 / 1500), 0.01));

    final learned = etaRemainingOnLeg(
      etaMinutes: 7,
      gpsMeters: 500,
      hops: const [
        MapLegHop(fromSeq: 1, toSeq: 2, meters: 1000, learnedSeconds: 100),
        MapLegHop(fromSeq: 2, toSeq: 3, meters: 1000, learnedSeconds: 300),
      ],
    );
    // Remainder is half of 100s, then 300s. Share 50/350 of 7 minutes.
    expect(learned, closeTo(7 * 60 * (50 / 350), 0.01));
  });

  test('the same ETA to a further stop spends less time on this leg', () {
    double movedToward(int stopSeq) {
      final bus = route();
      addTearDown(bus.dispose);
      bus.selectStop(stopSeq);
      final t0 = DateTime.utc(2026, 10, 8, 8);
      bus.allBusesList = [_bus(lat: 22.195, speed: 0, seq: 1, etaMinutes: 8)];
      bus.advanceBusMotion(t0);
      final atFix = bus.snapBusToStop(bus.allBusesList.single)!;
      bus.advanceBusMotion(t0.add(const Duration(seconds: 10)));
      return apart(bus.snapBusToStop(bus.allBusesList.single)!, atFix);
    }

    final nextStop = movedToward(2);
    final furtherStop = movedToward(3);
    expect(furtherStop, greaterThan(nextStop + 8));
  });

  test('atStop places the bus at the stop even when ETA still has minutes', () {
    final bus = route();
    addTearDown(bus.dispose);
    bus.selectStop(2);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.195, speed: 0, seq: 1, etaMinutes: 10)];
    bus.advanceBusMotion(t0);
    bus.advanceBusMotion(t0.add(const Duration(seconds: 5)));
    final before = bus.snapBusToStop(bus.allBusesList.single)!;

    bus.allBusesList = [
      _bus(lat: 22.20, speed: 0, seq: 2, atStop: true, etaMinutes: 0),
    ];
    bus.advanceBusMotion(t0.add(const Duration(seconds: 5)));
    final parked = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(parked, const LatLng(22.20, 113.54)), lessThan(25));
    expect(apart(parked, before), greaterThan(100));
  });

  test('a fix behind the icon stays put even if ETA is short', () {
    final bus = route();
    addTearDown(bus.dispose);
    bus.selectStop(2);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.195, speed: 36, seq: 1, etaMinutes: 8)];
    bus.advanceBusMotion(t0);
    bus.advanceBusMotion(t0.add(const Duration(seconds: 4)));
    final ahead = bus.snapBusToStop(bus.allBusesList.single)!;

    final backAt = t0.add(const Duration(seconds: 4));
    bus.allBusesList = [_bus(lat: 22.192, speed: 36, seq: 1, etaMinutes: 1)];
    bus.advanceBusMotion(backAt);
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, ahead), lessThan(5));
    bus.advanceBusMotion(backAt.add(const Duration(seconds: 3)));
    final held = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(held, ahead), lessThan(5));
    expect(held.latitude, greaterThan(22.192));
  });

  test('clearing the selected-stop ETA stops the time glide', () {
    final bus = route();
    addTearDown(bus.dispose);
    bus.selectStop(2);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [_bus(lat: 22.195, speed: 0, seq: 1, etaMinutes: 2)];
    bus.advanceBusMotion(t0);
    final atFix = bus.snapBusToStop(bus.allBusesList.single)!;
    bus.advanceBusMotion(t0.add(const Duration(seconds: 8)));
    final mid = bus.snapBusToStop(bus.allBusesList.single)!;
    expect(apart(mid, atFix), greaterThan(15));

    bus.selectStop(3);
    bus.advanceBusMotion(t0.add(const Duration(seconds: 18)));
    expect(apart(bus.snapBusToStop(bus.allBusesList.single)!, mid), lessThan(5));
  });

  test('a learned segment duration glides a later bus from the stop', () {
    final bus = route();
    addTearDown(bus.dispose);
    final t0 = DateTime.utc(2026, 10, 8, 8);
    bus.allBusesList = [
      _bus(lat: 22.19, speed: 0, seq: 1, atStop: true, plate: 'TRAIN'),
    ];
    bus.advanceBusMotion(t0);
    final left = t0.add(const Duration(seconds: 1));
    bus.allBusesList = [_bus(lat: 22.1903, speed: 0, seq: 1, plate: 'TRAIN')];
    bus.advanceBusMotion(left);
    bus.allBusesList = [
      _bus(lat: 22.20, speed: 0, seq: 2, atStop: true, plate: 'TRAIN'),
    ];
    bus.advanceBusMotion(left.add(const Duration(seconds: 100)));

    final t1 = left.add(const Duration(seconds: 110));
    bus.allBusesList = [
      _bus(lat: 22.19, speed: 0, seq: 1, atStop: true, plate: 'RIDER'),
    ];
    bus.advanceBusMotion(t1);
    final go = t1.add(const Duration(seconds: 1));
    bus.allBusesList = [_bus(lat: 22.1903, speed: 0, seq: 1, plate: 'RIDER')];
    bus.advanceBusMotion(go);
    final started = bus.snapBusToStop(bus.allBusesList.single)!;

    bus.advanceBusMotion(go.add(const Duration(seconds: 40)));
    final later = bus.snapBusToStop(bus.allBusesList.single)!;
    const from = LatLng(22.19, 113.54);
    const fix = LatLng(22.1903, 113.54);
    final length = distance.as(LengthUnit.Meter, from, const LatLng(22.20, 113.54));
    final gps = distance.as(LengthUnit.Meter, from, fix);
    final ref = length * (40 / 100);
    final blended = gps * (1 - BusController.mapEtaBlend) + ref * BusController.mapEtaBlend;
    expect(apart(later, started), greaterThan(80));
    expectMoved(apart(later, from), blended);
    expect(apart(later, const LatLng(22.20, 113.54)), greaterThan(200));
  });
}
