import 'package:flutter_test/flutter_test.dart';
import 'package:macau_bus_app/utils/boarding_bus_choice.dart';

const double _lat0 = 22.19;
const double _lng = 113.54;
const double _latMeters = 110540;

double _north(double meters) => _lat0 + meters / _latMeters;

BoardingPoint _stop(int seq, double meters) => BoardingPoint(_north(meters), _lng, seq: seq);

BoardingBusInput _bus(String license, int seq, double meters) {
  return BoardingBusInput(
    license: license,
    lat: _north(meters),
    lng: _lng,
    currentStopSeq: seq,
  );
}

void main() {
  final stops = [_stop(1, 0), _stop(2, 500), _stop(3, 1000), _stop(4, 1500)];
  final target = _stop(4, 1500);

  BoardingChoice choose({
    required List<BoardingBusInput> buses,
    Map<String, BoardingPoint> lastRecorded = const {},
  }) {
    return chooseBoardingBus(
      buses: buses,
      targetSeq: 4,
      target: target,
      stops: stops,
      routePoints: const [],
      lastRecorded: lastRecorded,
    );
  }

  test('picks the nearest bus still before the stop, not the one already past', () {
    final choice = choose(buses: [
      _bus('past', 3, 1560),
      _bus('far', 1, 100),
      _bus('close', 2, 1200),
    ]);

    expect(choice.ok, isTrue);
    expect(choice.license, 'close');
    expect(choice.usedLastRecorded, isFalse);
    expect(choice.failure, isNull);
  });

  test('uses the last recorded coordinates when the current fix is unusable', () {
    final choice = choose(
      buses: const [
        BoardingBusInput(license: 'AA', lat: 0, lng: 0, currentStopSeq: 2),
      ],
      lastRecorded: {'AA': _stop(0, 1200)},
    );

    expect(choice.license, 'AA');
    expect(choice.usedLastRecorded, isTrue);
    expect(choice.lat, closeTo(_north(1200), 0.0000001));
    expect(choice.lng, _lng);
  });

  test('does not substitute a farther bus when the nearest has no recorded position', () {
    final choice = choose(buses: [
      const BoardingBusInput(license: 'near', lat: 0, lng: 0, currentStopSeq: 3),
      _bus('farther', 1, 100),
    ]);

    expect(choice.ok, isFalse);
    expect(choice.license, isNull);
    expect(choice.failure, BoardingChoiceFailure.noRecordedPosition);
  });

  test('a bus whose coordinates are past the stop is excluded even if its sequence is behind', () {
    final choice = choose(buses: [
      _bus('past', 2, 1700),
      _bus('before', 1, 200),
    ]);

    expect(choice.license, 'before');
    expect(choice.license, isNot('past'));
  });

  test('only one bus is chosen', () {
    final choice = choose(buses: [
      _bus('past', 3, 1560),
      _bus('far', 1, 100),
      _bus('close', 2, 1200),
    ]);

    expect([choice.license], ['close']);
  });
}
