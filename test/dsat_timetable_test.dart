import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macau_bus_app/services/dsat_timetable.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await DsatTimetable.ensureLoaded();
  });

  test('route 1A has DSAT weekday and Sunday frequency bands both ways', () {
    for (final dir in [0, 1]) {
      final sections = DsatTimetable.sectionsFor('1A', dir);
      expect(sections.map((s) => s.title), [
        '星期一至六（公眾假期除外）',
        '星期日及公眾假期',
      ]);
      expect(sections.first.items.first.time, '06:00-07:00');
      expect(sections.first.items.first.freq, '9 - 11');
      expect(sections.first.items.last.time, '20:00-00:10');
      expect(sections.first.items.last.freq, '12 - 15');
      expect(sections.last.items.first.time, '06:00-20:00');
      expect(sections.last.items.first.freq, '10 - 12');
    }
    expect(DsatTimetable.sectionsFor('1a', 0).length, 2);
  });

  test('directions keep their own last band', () {
    final toBarra = DsatTimetable.sectionsFor('1', 0).first.items.last.time;
    final toBorder = DsatTimetable.sectionsFor('1', 1).first.items.last.time;
    expect(toBarra, '20:00-01:15');
    expect(toBorder, '20:00-00:45');
  });

  test('a circular route is shown for either direction index', () {
    final forward = DsatTimetable.sectionsFor('52', 0);
    final flipped = DsatTimetable.sectionsFor('52', 1);
    expect(forward.map((s) => s.title), flipped.map((s) => s.title));
    expect(forward.map((s) => s.title), [
      '星期一至五（公眾假期除外）',
      '星期六（公眾假期除外）',
      '星期日及公眾假期',
    ]);
    expect(forward.first.items.first.freq, '4 - 10');
    expect(forward.last.items.first.freq, '8 - 12');
  });

  test('the bundled file covers the DSAT scrape, including exact clocks', () {
    expect(DsatTimetable.routeCount, 101);
    expect(DsatTimetable.hasRoute('2'), isTrue);

    final toBarraSun = DsatTimetable.sectionsFor('2', 0).last;
    expect(toBarraSun.title, '星期日及公眾假期');
    expect(toBarraSun.items.first.time, '06:15-19:00');
    expect(toBarraSun.items.first.freq, '6 - 12');
    expect(toBarraSun.items.last.time, '19:00-00:00');
    expect(DsatTimetable.sectionsFor('2', 1).last.items.first.time, '06:30-19:00');

    final departures = DsatTimetable.sectionsFor('71S', 0);
    expect(departures.first.items.first.time, '08:25');
    expect(departures.first.items.first.freq, '—');
    expect(departures.last.items.single.freq, '服務暫停 / SERVIÇO SUSPENSO');
    expect(DsatTimetable.sectionsFor('71S', 1).first.items.first.time, '07:35');
  });

  test('corrected circular and dated routes keep the published bands', () {
    final peak = DsatTimetable.sectionsFor('25BS', 0);
    expect(peak.map((s) => s.title), [
      '星期一至六（強制性假日除外）',
      '星期日及強制性假日',
    ]);
    expect(peak.first.items.map((i) => i.time), ['06:30-09:30', '17:00-19:00']);
    expect(peak.last.items.single.freq, '服務暫停 / SERVIÇO SUSPENSO');
    expect(DsatTimetable.sectionsFor('25BS', 1).map((s) => s.title), peak.map((s) => s.title));

    expect(DsatTimetable.sectionsFor('26AT', 0).single.title, '2026年9月25-27日及2026年10月1-7日');
    expect(DsatTimetable.sectionsFor('26AT', 0).single.items.single.freq, '15 - 30');

    const night = '2026年9月12日、19日、25日及2026年10月1日、4日';
    final oneWay = DsatTimetable.sectionsFor('3AS', 0);
    expect(oneWay.single.title, night);
    expect(oneWay.single.items.single.time, '21:30-23:00');
    expect(oneWay.single.items.single.freq, '15 - 20');
    expect(DsatTimetable.sectionsFor('3AS', 1).single.title, night);
    expect(DsatTimetable.sectionsFor('17S1', 0).single.items.single.freq, '10 - 30');
    expect(DsatTimetable.sectionsFor('26S', 0).single.items.single.time, '21:30-23:00');
    expect(DsatTimetable.sectionsFor('52S', 0).single.items.single.time, '20:30-23:00');
    expect(DsatTimetable.sectionsFor('52S', 0).single.items.single.freq, '15 - 20');
  });

  test('bundled service windows stay first and last times', () async {
    final raw = await rootBundle.loadString('assets/timetable.json');
    final map = jsonDecode(raw) as Map<String, dynamic>;
    expect(map['1A_0'], {'startTime': '06:00', 'endTime': '00:10'});
    expect(map['1A_1'], {'startTime': '06:00', 'endTime': '00:10'});
    expect(map.containsKey('routes'), isFalse);
    expect(map.containsKey('schema'), isFalse);
  });

  test('a route with no DSAT bands is empty', () {
    expect(DsatTimetable.hasRoute('99Z'), isFalse);
    expect(DsatTimetable.sectionsFor('99Z', 0), isEmpty);
    expect(DsatTimetable.sectionsFor('', 0), isEmpty);
  });
}
