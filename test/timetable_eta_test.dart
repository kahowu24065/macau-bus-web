import 'package:flutter_test/flutter_test.dart';
import 'package:macau_bus_app/services/dsat_timetable.dart';
import 'package:macau_bus_app/utils/timetable_eta.dart';
import 'package:macau_bus_app/views/widgets/timetable_dialog.dart';

void main() {
  final route1 = const [
    DsatFrequencyBand(time: '06:00-10:00', freq: '4 - 8'),
    DsatFrequencyBand(time: '10:00-15:00', freq: '10 - 12'),
    DsatFrequencyBand(time: '15:00-20:00', freq: '4 - 8'),
    DsatFrequencyBand(time: '20:00-01:15', freq: '10 - 12'),
  ];

  test('before the first band, minutes run until that opening', () {
    expect(
      timetableArrivalMinutes(
        rows: route1,
        now: DateTime(2026, 10, 14, 5, 30),
        travelMinutes: 0,
      ),
      30,
    );
    expect(
      timetableArrivalMinutes(
        rows: route1,
        now: DateTime(2026, 10, 14, 5, 50),
        travelMinutes: 20,
      ),
      30,
    );
  });

  test('the opening bus is still estimated while it can be on the way', () {
    expect(
      timetableArrivalMinutes(
        rows: route1,
        now: DateTime(2026, 10, 14, 6, 5),
        travelMinutes: 20,
      ),
      15,
    );
    expect(
      timetableArrivalMinutes(
        rows: route1,
        now: DateTime(2026, 10, 14, 6, 30),
        travelMinutes: 20,
      ),
      isNull,
    );
    expect(
      timetableArrivalMinutes(
        rows: route1,
        now: DateTime(2026, 10, 14, 0, 30),
        travelMinutes: 0,
      ),
      isNull,
    );
  });

  test('a gap between bands is the next opening, not a headway guess', () {
    const split = [
      DsatFrequencyBand(time: '06:30-09:30', freq: '8 - 12'),
      DsatFrequencyBand(time: '17:00-19:00', freq: '8 - 12'),
    ];
    expect(
      timetableArrivalMinutes(
        rows: split,
        now: DateTime(2026, 10, 14, 12, 0),
        travelMinutes: 0,
      ),
      300,
    );
    expect(
      timetableArrivalMinutes(
        rows: split,
        now: DateTime(2026, 10, 14, 8, 0),
        travelMinutes: 0,
      ),
      isNull,
    );
    expect(
      timetableArrivalMinutes(
        rows: split,
        now: DateTime(2026, 10, 14, 17, 5),
        travelMinutes: 20,
      ),
      15,
    );
  });

  test('after the last bus, the next day opening is used', () {
    const day = [
      DsatFrequencyBand(time: '06:00-23:00', freq: '10 - 12'),
    ];
    expect(
      timetableArrivalMinutes(
        rows: day,
        now: DateTime(2026, 10, 14, 23, 30),
        travelMinutes: 0,
        nextDayRows: day,
      ),
      390,
    );
  });

  test('a suspended day does not borrow tomorrow', () {
    const closed = [
      DsatFrequencyBand(time: '—', freq: '服務暫停 / SERVIÇO SUSPENSO'),
    ];
    expect(
      timetableArrivalMinutes(
        rows: closed,
        now: DateTime(2026, 10, 18, 12, 0),
        travelMinutes: 0,
        nextDayRows: route1,
      ),
      isNull,
    );
  });

  test('exact clocks use the next departure, including one already en route', () {
    const clocks = [
      DsatFrequencyBand(time: '08:25', freq: '—'),
      DsatFrequencyBand(time: '08:40', freq: '—'),
    ];
    expect(
      timetableArrivalMinutes(
        rows: clocks,
        now: DateTime(2026, 10, 14, 8, 0),
        travelMinutes: 0,
      ),
      25,
    );
    expect(
      timetableArrivalMinutes(
        rows: clocks,
        now: DateTime(2026, 10, 14, 8, 26),
        travelMinutes: 10,
      ),
      9,
    );
    expect(
      timetableArrivalMinutes(
        rows: clocks,
        now: DateTime(2026, 10, 14, 9, 0),
        travelMinutes: 0,
      ),
      isNull,
    );
  });

  test('bundled route 1 and 71S follow the same rules', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await DsatTimetable.ensureLoaded();
    final wednesday = DateTime(2026, 10, 14, 5, 30);
    final sections = DsatTimetable.sectionsFor('1', 0);
    final today = timetableSectionIndexFor(sections, wednesday);
    expect(
      timetableArrivalMinutes(
        rows: sections[today].items,
        now: wednesday,
        travelMinutes: 0,
      ),
      30,
    );
    expect(
      timetableArrivalMinutes(
        rows: sections[today].items,
        now: DateTime(2026, 10, 14, 10, 0),
        travelMinutes: 0,
      ),
      isNull,
    );

    final exact = DsatTimetable.sectionsFor('71S', 0);
    final exactToday = timetableSectionIndexFor(exact, wednesday);
    expect(
      timetableArrivalMinutes(
        rows: exact[exactToday].items,
        now: DateTime(2026, 10, 14, 8, 0),
        travelMinutes: 0,
      ),
      25,
    );
    final sunday = DateTime(2026, 10, 18, 8, 0);
    final sundayIndex = timetableSectionIndexFor(exact, sunday);
    final monday = timetableSectionIndexFor(exact, sunday.add(const Duration(days: 1)));
    expect(
      timetableArrivalMinutes(
        rows: exact[sundayIndex].items,
        now: sunday,
        travelMinutes: 0,
        nextDayRows: exact[monday].items,
      ),
      isNull,
    );
  });

  test('travel time is stop-to-stop at 22 km/h plus dwell, or nothing', () {
    const origin = TimetableStopPoint(1, 22.19000, 113.54000);
    // About 500 m north of the origin.
    const next = TimetableStopPoint(2, 22.19452, 113.54000);
    const third = TimetableStopPoint(3, 22.19904, 113.54000);
    expect(timetableTravelMinutes(const [origin], 1), 0);
    expect(timetableTravelMinutes(const [origin, next], 2), 1);
    expect(timetableTravelMinutes(const [origin, next, third], 3), 3);
    expect(
      timetableTravelMinutes(
        const [origin, TimetableStopPoint(2, 0, 0), third],
        3,
      ),
      isNull,
    );
  });

  test('realtime minutes and a live bus are left alone', () {
    const label = '時間表 約 12 分鐘';
    expect(
      withTimetableEta(
        upcoming: const [],
        timetableLabel: label,
        noServiceToday: '本日不設服務',
      ),
      [
        {'status': label, 'plate': ''},
      ],
    );
    expect(
      withTimetableEta(
        upcoming: const [
          {'status': '下站到達 (約 4 分鐘)', 'plate': 'MB1'},
        ],
        timetableLabel: label,
        noServiceToday: '本日不設服務',
      ).single['status'],
      '下站到達 (約 4 分鐘)',
    );
    expect(
      withTimetableEta(
        upcoming: const [
          {'status': '尚有 3 站', 'plate': 'MB1'},
        ],
        timetableLabel: label,
        noServiceToday: '本日不設服務',
      ).single['status'],
      '尚有 3 站',
    );
    final replaced = withTimetableEta(
      upcoming: const [
        {'status': '本日服務尚未開始', 'plate': ''},
        {'status': '等候總站發車', 'plate': ''},
      ],
      timetableLabel: label,
      noServiceToday: '本日不設服務',
    );
    expect(replaced, [
      {'status': label, 'plate': ''},
    ]);
    expect(
      withTimetableEta(
        upcoming: const [
          {'status': '本日不設服務', 'plate': ''},
        ],
        timetableLabel: label,
        noServiceToday: '本日不設服務',
      ).single['status'],
      '本日不設服務',
    );
    expect(
      withTimetableEta(
        upcoming: const [
          {'status': '點擊更新', 'plate': ''},
        ],
        timetableLabel: null,
        noServiceToday: '本日不設服務',
      ).single['status'],
      '點擊更新',
    );
  });
}
