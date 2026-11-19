import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:macau_bus_app/services/dsat_timetable.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    DsatTimetable.debugFetch = (_) async => http.Response('offline', 503);
    await DsatTimetable.ensureLoaded();
    await DsatTimetable.debugRefreshInFlight;
  });

  test('route 1A has DSAT weekday and Sunday frequency bands both ways', () {
    for (final dir in [0, 1]) {
      final sections = DsatTimetable.sectionsFor('1A', dir);
      expect(sections.map((s) => s.title), ['星期一至六（公眾假期除外）', '星期日及公眾假期']);
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
    expect(DsatTimetable.routeCount, 103);
    expect(DsatTimetable.hasRoute('2'), isTrue);

    final toBarraSun = DsatTimetable.sectionsFor('2', 0).last;
    expect(toBarraSun.title, '星期日及公眾假期');
    expect(toBarraSun.items.first.time, '06:15-19:00');
    expect(toBarraSun.items.first.freq, '6 - 12');
    expect(toBarraSun.items.last.time, '19:00-00:00');
    expect(
      DsatTimetable.sectionsFor('2', 1).last.items.first.time,
      '06:30-19:00',
    );

    final departures = DsatTimetable.sectionsFor('71S', 0);
    expect(departures.first.items.first.time, '08:25');
    expect(departures.first.items.first.freq, '—');
    expect(departures.last.items.single.freq, '服務暫停 / SERVIÇO SUSPENSO');
    expect(DsatTimetable.sectionsFor('71S', 1).first.items.first.time, '07:35');
  });

  test('corrected circular and dated routes keep the published bands', () {
    final peak = DsatTimetable.sectionsFor('25BS', 0);
    expect(peak.map((s) => s.title), ['星期一至六（強制性假日除外）', '星期日及強制性假日']);
    expect(peak.first.items.map((i) => i.time), ['06:30-09:30', '17:00-19:00']);
    expect(peak.last.items.single.freq, '服務暫停 / SERVIÇO SUSPENSO');
    expect(
      DsatTimetable.sectionsFor('25BS', 1).map((s) => s.title),
      peak.map((s) => s.title),
    );

    expect(
      DsatTimetable.sectionsFor('26AT', 0).single.title,
      '2026年9月25-27日及2026年10月1-7日',
    );
    expect(
      DsatTimetable.sectionsFor('26AT', 0).single.items.single.freq,
      '15 - 30',
    );

    const night = '2026年9月12日、19日、25日及2026年10月1日、4日';
    final oneWay = DsatTimetable.sectionsFor('3AS', 0);
    expect(oneWay.single.title, night);
    expect(oneWay.single.items.single.time, '21:30-23:00');
    expect(oneWay.single.items.single.freq, '15 - 20');
    expect(DsatTimetable.sectionsFor('3AS', 1).single.title, night);
    expect(
      DsatTimetable.sectionsFor('17S1', 0).single.items.single.freq,
      '10 - 30',
    );
    expect(
      DsatTimetable.sectionsFor('26S', 0).single.items.single.time,
      '21:30-23:00',
    );
    expect(
      DsatTimetable.sectionsFor('52S', 0).single.items.single.time,
      '20:30-23:00',
    );
    expect(
      DsatTimetable.sectionsFor('52S', 0).single.items.single.freq,
      '15 - 20',
    );
    expect(
      DsatTimetable.sectionsFor('52S', 1).single.title,
      DsatTimetable.sectionsFor('52S', 0).single.title,
    );
  });

  test('PDF corrections split Saturday and name suspended days', () {
    expect(DsatTimetable.sectionsFor('6B', 0).map((s) => s.title), [
      '星期一至六（強制性假日除外）',
      '星期日及強制性假日',
    ]);
    expect(
      DsatTimetable.sectionsFor('6B', 0).last.items.single.freq,
      '服務暫停 / SERVIÇO SUSPENSO',
    );

    final route4 = DsatTimetable.sectionsFor('4', 0);
    expect(route4.map((s) => s.title), [
      '星期一至五（公眾假期除外）',
      '星期六（公眾假期除外）',
      '星期日及公眾假期',
    ]);
    expect(route4[1].items[2].time, '10:00-20:00');
    expect(route4[1].items[2].freq, '10 - 12');
    expect(route4.last.items.first.time, '06:00-20:00');
    expect(route4.last.items.first.freq, '12 - 15');

    final toBarra = DsatTimetable.sectionsFor('18', 0);
    final toCurrais = DsatTimetable.sectionsFor('18', 1);
    expect(toBarra.first.items.map((i) => i.time), [
      '06:00-10:00',
      '10:00-15:00',
      '15:00-20:00',
      '20:00-01:10',
    ]);
    expect(toCurrais.first.items.first.time, '05:45-10:00');
    expect(toCurrais.last.items.last.time, '20:00-00:40');

    expect(
      DsatTimetable.sectionsFor('701XS', 0).last.items.single.freq,
      '服務暫停 / SERVIÇO SUSPENSO',
    );
    expect(DsatTimetable.sectionsFor('H2', 0).last.title, '星期六、日及強制性假日');
    expect(
      DsatTimetable.sectionsFor('101XS', 0).single.title,
      '2026年9月25-27日及2026年10月1-7日',
    );
    expect(DsatTimetable.sectionsFor('18B', 1)[1].title, '星期六（公眾假期除外）');
    expect(
      DsatTimetable.sectionsFor('18B', 0).last.items.first.time,
      '07:00-16:00',
    );
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

  test('12T and 31T keep the Grand Prix shuttle bands', () {
    for (final route in ['12T', '31T', '12t']) {
      for (final direction in [0, 1]) {
        final sections = DsatTimetable.sectionsFor(route, direction);
        expect(sections.map((section) => section.title), [
          '2026年11月19-21日',
          '2026年11月22日',
        ]);
        expect(sections.first.items.single.time, '06:00-00:30');
        expect(sections.first.items.single.freq, '12 - 20');
        expect(sections.last.items.single.time, '06:00-19:00');
        expect(sections.last.items.single.freq, '12 - 20');
      }
    }
    expect(DsatTimetable.usingServerCopy, isFalse);
  });

  test('the server sample matches the bundled frequency file', () {
    final bundled = File('assets/dsat_timetables.json').readAsStringSync();
    final sample = File('server/dsat_timetables.json').readAsStringSync();
    expect(sample, bundled);
    final server = File('server/dsat_timetables.js').readAsStringSync();
    expect(
      server,
      contains('const MIN_ROUTES = ${DsatTimetable.minServerRoutes}'),
    );
    expect(server, contains("const SCHEMA = '${DsatTimetable.schema}'"));
    expect(server, contains('/api/dsat_timetables.json'));
    expect(server, isNot(contains('motransportinfo')));
    expect(server, isNot(contains('bis.dsat.gov.mo')));
    final client = File('lib/services/dsat_timetable.dart').readAsStringSync();
    expect(client, contains("'\${ApiConfig.api}/dsat_timetables.json'"));
    expect(client, isNot(contains('motransportinfo')));
    expect(client, isNot(contains('bis.dsat.gov.mo')));
    expect(client, isNot(contains("ApiConfig.api}/timetable.json")));
  });

  group('server frequency refresh', () {
    tearDown(() async {
      await DsatTimetable.debugRefreshInFlight;
      DsatTimetable.debugReset();
      DsatTimetable.debugFetch = (_) async => http.Response('offline', 503);
      await DsatTimetable.ensureLoaded();
      await DsatTimetable.debugRefreshInFlight;
    });

    test('a full frequency file replaces the bundled bands', () async {
      final notices = <int>[];
      void onUpdate() => notices.add(DsatTimetable.routeCount);
      DsatTimetable.addListener(onUpdate);
      addTearDown(() => DsatTimetable.removeListener(onUpdate));

      await _refresh(
        _body({'ZZT': _appRoute('08:15-09:45', '5-7', title: '2026年11月19日')}),
      );

      expect(DsatTimetable.usingServerCopy, isTrue);
      expect(DsatTimetable.hasRoute('1A'), isFalse);
      expect(notices, [DsatTimetable.minServerRoutes + 1]);
      for (final direction in [0, 1]) {
        final band = DsatTimetable.sectionsFor(
          'ZZT',
          direction,
        ).single.items.single;
        expect(band.time, '08:15-09:45');
        expect(band.freq, '5 - 7');
      }
    });

    test('a legacy directions object counts toward the full file', () async {
      await _refresh(
        _body({
          'LEG': {
            'directions': {
              '0': {
                'sections': [
                  {
                    'title': '2026年11月22日',
                    'items': [
                      {'time': '06:00-19:00', 'freq': '12-20'},
                    ],
                  },
                ],
              },
            },
          },
        }, fillers: DsatTimetable.minServerRoutes - 1),
      );

      expect(DsatTimetable.usingServerCopy, isTrue);
      final band = DsatTimetable.sectionsFor('LEG', 1).single.items.single;
      expect(band.time, '06:00-19:00');
      expect(band.freq, '12 - 20');
    });

    test(
      'errors, challenges, and short or wrong files keep the current map',
      () async {
        var notices = 0;
        void onUpdate() => notices++;
        DsatTimetable.addListener(onUpdate);
        addTearDown(() => DsatTimetable.removeListener(onUpdate));

        Future<void> rejected(Future<http.Response> Function() send) async {
          final before = DsatTimetable.sectionsFor(
            '1A',
            0,
          ).first.items.first.freq;
          DsatTimetable.debugFetch = (_) => send();
          DsatTimetable.debugExpire();
          await DsatTimetable.ensureLoaded();
          await DsatTimetable.debugRefreshInFlight;
          expect(DsatTimetable.usingServerCopy, isFalse);
          expect(
            DsatTimetable.sectionsFor('1A', 0).first.items.first.freq,
            before,
          );
          expect(DsatTimetable.hasRoute('12T'), isTrue);
        }

        await rejected(
          () async => _response('<!DOCTYPE html><html></html>', 200),
        );
        await rejected(
          () async =>
              _response(_body({'ZZT': _appRoute('01:00-02:00', '3-4')}), 403),
        );
        await rejected(() async => _response('nope', 404));
        await rejected(
          () async => _response(
            _body({}, fillers: DsatTimetable.minServerRoutes - 1),
            200,
          ),
        );
        await rejected(
          () async => _response(
            _body({'ZZT': _appRoute('01:00-02:00', '3-4')}, schema: 'other'),
            200,
          ),
        );
        await rejected(
          () async => _response(
            jsonEncode({
              'date': '20261119',
              'routes': {
                for (var i = 0; i < 80; i++)
                  '1A_$i': {'startTime': '06:00', 'endTime': '00:30'},
              },
            }),
            200,
          ),
        );
        await rejected(
          () async => _response(
            jsonEncode({
              'schema': DsatTimetable.schema,
              'routes': {
                for (var i = 0; i < 80; i++)
                  'R$i': {
                    'directions': [
                      {'rows': []},
                    ],
                  },
              },
            }),
            200,
          ),
        );
        await rejected(() async => throw Exception('offline'));
        expect(notices, 0);
        expect(DsatTimetable.hasRoute('ZZT'), isFalse);
      },
    );

    test(
      'a failed attempt waits out the refresh interval, then tries once',
      () async {
        var calls = 0;
        final gate = Completer<http.Response>();
        DsatTimetable.debugFetch = (_) {
          calls++;
          return gate.future;
        };
        DsatTimetable.debugExpire();
        await DsatTimetable.ensureLoaded();
        await DsatTimetable.ensureLoaded();
        expect(calls, 1);

        gate.complete(http.Response('offline', 503));
        await DsatTimetable.debugRefreshInFlight;
        await DsatTimetable.ensureLoaded();
        expect(calls, 1);
        expect(DsatTimetable.hasRoute('31T'), isTrue);

        DsatTimetable.debugExpire();
        await DsatTimetable.ensureLoaded();
        await DsatTimetable.debugRefreshInFlight;
        expect(calls, 2);
        expect(
          DsatTimetable.frequencyUri.toString(),
          'https://macaubus-kat1.com/api/dsat_timetables.json',
        );
      },
    );

    testWidgets('a timed-out refresh keeps the bundled bands', (tester) async {
      final hung = Completer<http.Response>();
      DsatTimetable.debugFetch = (_) => hung.future;
      DsatTimetable.debugExpire();
      await DsatTimetable.ensureLoaded();
      expect(DsatTimetable.hasRoute('12T'), isTrue);

      await tester.pump(const Duration(seconds: 6));
      expect(DsatTimetable.usingServerCopy, isFalse);
      expect(DsatTimetable.hasRoute('1A'), isTrue);

      hung.complete(
        _response(_body({'ZZT': _appRoute('01:00-02:00', '3-4')}), 200),
      );
      await tester.pump();
      expect(DsatTimetable.hasRoute('ZZT'), isFalse);
      expect(DsatTimetable.hasRoute('12T'), isTrue);
    });
  });
}

Map<String, dynamic> _appRoute(
  String time,
  String freq, {
  String title = '2026年11月19日',
}) {
  return {
    'app_frequency': {
      'sections': [
        {
          'title': title,
          'directions': [
            {
              'rows': [
                {'服務時間': time, '班次(分鐘)': freq},
              ],
            },
          ],
        },
      ],
    },
  };
}

String _body(Map<String, dynamic> extra, {int? fillers, String? schema}) {
  final count = fillers ?? DsatTimetable.minServerRoutes;
  final routes = <String, dynamic>{
    for (var i = 0; i < count; i++) 'F$i': _appRoute('06:00-07:00', '10-12'),
  };
  routes.addAll(extra);
  return jsonEncode({
    'schema': schema ?? DsatTimetable.schema,
    'routes': routes,
  });
}

http.Response _response(String body, int status) {
  return http.Response.bytes(
    utf8.encode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

Future<List<Uri>> _refresh(String body, {int status = 200}) async {
  final uris = <Uri>[];
  DsatTimetable.debugFetch = (uri) async {
    uris.add(uri);
    return _response(body, status);
  };
  DsatTimetable.debugExpire();
  await DsatTimetable.ensureLoaded();
  await DsatTimetable.debugRefreshInFlight;
  expect(uris.single.toString(), DsatTimetable.frequencyUri.toString());
  return uris;
}
