import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:macau_bus_app/constants/app_translations.dart';
import 'package:macau_bus_app/controllers/easy_read_mode_controller.dart';
import 'package:macau_bus_app/controllers/language_controller.dart';
import 'package:macau_bus_app/services/dsat_timetable.dart';
import 'package:macau_bus_app/theme/easy_read_theme.dart';
import 'package:macau_bus_app/utils/service_label_i18n.dart';
import 'package:macau_bus_app/views/widgets/easy_read_tap_haptics.dart';
import 'package:macau_bus_app/views/widgets/preserve_chrome.dart';
import 'package:macau_bus_app/views/widgets/timetable_dialog.dart';

const _gold = Color(0xFFFFC107);
final _wednesday = DateTime(2026, 10, 7);
final _saturday = DateTime(2026, 10, 10);
final _sunday = DateTime(2026, 10, 11);

DsatTimetableSection _section(String title) => DsatTimetableSection(
  title: title,
  items: const [DsatFrequencyBand(time: '06:00-08:00', freq: '10-12')],
);

Future<void> _loadRoboto() async {
  var dir = File(Platform.resolvedExecutable).parent;
  Directory? fonts;
  for (var i = 0; i < 8 && fonts == null; i++) {
    final candidate = Directory('${dir.path}/artifacts/material_fonts');
    if (candidate.existsSync()) fonts = candidate;
    dir = dir.parent;
  }
  if (fonts == null) {
    throw StateError('Roboto fonts were not found next to the Flutter SDK');
  }
  final loader = FontLoader('Roboto');
  for (final name in [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]) {
    final bytes = await File('${fonts.path}/$name').readAsBytes();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

/// Easy Read's dialog text styles omit [TextStyle.fontFamily]. Put the test
/// font back so Latin labels measure like a device font instead of the
/// square test fallback.
ThemeData _easyReadTheme(ThemeData base) {
  final applied = EasyReadTheme.apply(base);
  final family = base.textTheme.bodyMedium?.fontFamily;
  if (family == null) return applied;
  final dialog = applied.dialogTheme;
  return applied.copyWith(
    dialogTheme: dialog.copyWith(
      titleTextStyle: dialog.titleTextStyle?.copyWith(fontFamily: family),
      contentTextStyle: dialog.contentTextStyle?.copyWith(fontFamily: family),
    ),
  );
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  required String route,
  required int direction,
  String language = 'zh',
  DateTime? today,
  bool liveClock = false,
  bool easyRead = false,
  Brightness brightness = Brightness.dark,
}) async {
  SharedPreferences.setMockInitialValues({'language_code': language});
  final lang = LanguageController();
  await lang.changeLanguage(language);
  final easyReadMode = EasyReadModeController.fixed(easyRead);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<LanguageController>.value(value: lang),
        ChangeNotifierProvider<EasyReadModeController>.value(
          value: easyReadMode,
        ),
      ],
      child: MaterialApp(
        key: UniqueKey(),
        builder: (context, child) {
          final on = context.watch<EasyReadModeController>().enabled;
          if (!on || child == null) return child ?? const SizedBox.shrink();
          final base = Theme.of(context);
          final mq = MediaQuery.of(context);
          final scaled = mq.textScaler.scale(1) * EasyReadTheme.textScale;
          return EasyReadChrome(
            baseTheme: base,
            child: MediaQuery(
              data: mq.copyWith(textScaler: TextScaler.linear(scaled)),
              child: Theme(
                data: _easyReadTheme(base),
                child: EasyReadTapHaptics(child: child),
              ),
            ),
          );
        },
        theme: ThemeData(brightness: brightness, fontFamily: 'Roboto'),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => TimetableDialog.show(
                context,
                route: route,
                direction: direction,
                today: liveClock ? null : (today ?? _wednesday),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  expect(
    Provider.of<EasyReadModeController>(
      tester.element(find.text('open')),
      listen: false,
    ).enabled,
    easyRead,
    reason: 'easy read flag before the dialog opens',
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

BoxDecoration _bandDecoration(WidgetTester tester) {
  final card = tester.widget<Container>(
    find.descendant(
      of: find.byKey(const ValueKey('timetable-band-0')),
      matching: find.byWidgetPredicate(
        (widget) => widget is Container && widget.decoration is BoxDecoration,
      ),
    ),
  );
  return card.decoration! as BoxDecoration;
}

int _keyedCount(WidgetTester tester, String prefix) {
  return tester
      .widgetList(
        find.byWidgetPredicate((widget) {
          final key = widget.key;
          return key is ValueKey<String> && key.value.startsWith(prefix);
        }),
      )
      .length;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await DsatTimetable.ensureLoaded();
    await _loadRoboto();
  });

  test('day selector defaults to the section that covers today', () {
    expect(timetableSectionIndexFor(const [], _wednesday), 0);

    final route1A = DsatTimetable.sectionsFor('1A', 0);
    expect(timetableSectionIndexFor(route1A, _wednesday), 0);
    expect(timetableSectionIndexFor(route1A, _saturday), 0);
    expect(timetableSectionIndexFor(route1A, _sunday), 1);

    final route52 = DsatTimetable.sectionsFor('52', 0);
    expect(timetableSectionIndexFor(route52, _wednesday), 0);
    expect(timetableSectionIndexFor(route52, _saturday), 1);
    expect(timetableSectionIndexFor(route52, _sunday), 2);

    final mandatory = DsatTimetable.sectionsFor('25BS', 0);
    expect(timetableSectionIndexFor(mandatory, _wednesday), 0);
    expect(timetableSectionIndexFor(mandatory, _saturday), 0);
    expect(timetableSectionIndexFor(mandatory, _sunday), 1);

    final exact = DsatTimetable.sectionsFor('71S', 0);
    expect(timetableSectionIndexFor(exact, _wednesday), 0);
    expect(timetableSectionIndexFor(exact, _saturday), 1);
    expect(timetableSectionIndexFor(exact, _sunday), 1);

    expect(
      timetableSectionIndexFor(
        DsatTimetable.sectionsFor('26AT', 0),
        _wednesday,
      ),
      0,
    );
    expect(
      timetableSectionIndexFor(
        DsatTimetable.sectionsFor('26AT', 0),
        DateTime(2026, 10, 8),
      ),
      0,
    );
  });

  test('dated sections win, and a shorter list beats a longer one', () {
    final sections = [
      _section('星期一至五（公眾假期除外）'),
      _section('2026年9月12日、19日、25日及2026年10月1日、4日'),
      _section('2026年9月25-27日及2026年10月1-7日'),
    ];
    expect(timetableSectionIndexFor(sections, DateTime(2026, 10, 7)), 2);
    expect(timetableSectionIndexFor(sections, DateTime(2026, 9, 26)), 2);
    expect(timetableSectionIndexFor(sections, DateTime(2026, 9, 25)), 1);
    expect(timetableSectionIndexFor(sections, DateTime(2026, 9, 12)), 1);
    expect(timetableSectionIndexFor(sections, DateTime(2026, 10, 1)), 1);
    expect(timetableSectionIndexFor(sections, DateTime(2026, 10, 8)), 0);
  });

  test('the narrowest weekday coverage wins, including UM holiday titles', () {
    final wide = [
      _section('星期一至日及公眾假期'),
      _section('星期一至五（公眾假期除外）'),
      _section('星期六、日及公眾假期'),
    ];
    expect(timetableSectionIndexFor(wide, _wednesday), 1);
    expect(timetableSectionIndexFor(wide, _saturday), 2);
    expect(timetableSectionIndexFor(wide, _sunday), 2);

    final um = [
      _section('星期一至五（公眾假期及澳門大學休假日除外）'),
      _section('星期六、日、公眾假期及澳門大學休假日'),
    ];
    expect(timetableSectionIndexFor(um, _wednesday), 0);
    expect(timetableSectionIndexFor(um, _saturday), 1);
    expect(timetableSectionIndexFor(um, _sunday), 1);
  });

  testWidgets('1A dialog shows today\'s bands as dark cards', (tester) async {
    await _pumpDialog(tester, route: '1A', direction: 0);

    expect(find.text('1A 時間表'), findsOneWidget);
    expect(find.text('服務時間'), findsNWidgets(5));
    expect(find.text('班次(分鐘)'), findsNWidgets(5));
    expect(find.text('頻率區間'), findsNothing);
    expect(find.text('星期一至六（公眾假期除外）'), findsOneWidget);
    expect(find.text('星期日及公眾假期'), findsOneWidget);
    expect(find.text('06:00 - 07:00'), findsOneWidget);
    expect(find.text('9 - 11'), findsOneWidget);
    expect(find.text('06:00 - 20:00'), findsNothing);
    expect(find.text('班次來自交通事務局（DSAT）官方路線資料'), findsOneWidget);
    expect(find.text('關閉'), findsOneWidget);
    expect(_keyedCount(tester, 'timetable-band-'), 5);
    expect(_keyedCount(tester, 'timetable-connector-'), 4);

    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect(dialog.backgroundColor, const Color(0xFF1E1E1E));
    expect(dialog.actionsAlignment, MainAxisAlignment.end);

    final ring = tester.widget<Container>(
      find.byKey(const Key('timetable-bus-ring')),
    );
    final ringDecoration = ring.decoration! as BoxDecoration;
    expect(ringDecoration.shape, BoxShape.circle);
    expect((ringDecoration.border! as Border).top.color, _gold);
    expect(
      find.descendant(
        of: find.byKey(const Key('timetable-bus-ring')),
        matching: find.byIcon(Icons.directions_bus),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.schedule), findsNWidgets(5));

    final cardDecoration = _bandDecoration(tester);
    expect(cardDecoration.color, const Color(0xFF2A2A2A));
    expect(cardDecoration.borderRadius, BorderRadius.circular(14));

    final selected = tester.widget<Material>(
      find.byKey(const ValueKey('timetable-day-selected')),
    );
    expect(selected.color, _gold);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('timetable-day-selected')),
        matching: find.text('星期一至六（公眾假期除外）'),
      ),
      findsOneWidget,
    );

    final selector = tester.widget<Container>(
      find.byKey(const Key('timetable-day-selector')),
    );
    final selectorDecoration = selector.decoration! as BoxDecoration;
    expect((selectorDecoration.border! as Border).top.color, _gold);
    expect(selectorDecoration.borderRadius, BorderRadius.circular(999));

    final close = tester.widget<FilledButton>(
      find.byKey(const Key('timetable-close')),
    );
    expect(close.style?.backgroundColor?.resolve(const <WidgetState>{}), _gold);
    expect(
      tester.widget<OverflowBar>(find.byType(OverflowBar)).alignment,
      MainAxisAlignment.end,
    );

    await tester.tap(find.text('星期日及公眾假期'));
    await tester.pumpAndSettle();
    expect(find.text('06:00 - 20:00'), findsOneWidget);
    expect(find.text('10 - 12'), findsWidgets);
    expect(find.text('9 - 11'), findsNothing);
    expect(find.text('06:00 - 07:00'), findsNothing);
    expect(_keyedCount(tester, 'timetable-band-'), 2);
    expect(_keyedCount(tester, 'timetable-connector-'), 1);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('timetable-day-selected')),
        matching: find.text('星期日及公眾假期'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('關閉'));
    await tester.pumpAndSettle();
    expect(find.text('1A 時間表'), findsNothing);
  });

  testWidgets('Saturday opens the Saturday segment on a three-way route', (
    tester,
  ) async {
    await _pumpDialog(tester, route: '52', direction: 0, today: _saturday);

    expect(find.text('星期一至五（公眾假期除外）'), findsOneWidget);
    expect(find.text('星期六（公眾假期除外）'), findsOneWidget);
    expect(find.text('星期日及公眾假期'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('timetable-day-selected')),
        matching: find.text('星期六（公眾假期除外）'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a route without bands fails with the empty state', (
    tester,
  ) async {
    await _pumpDialog(tester, route: '99Z', direction: 0);

    expect(find.text('99Z 時間表'), findsOneWidget);
    expect(find.text('暫無詳細時間表資料'), findsOneWidget);
    expect(find.text('服務時間'), findsNothing);
    expect(find.textContaining('DSAT'), findsNothing);
    expect(find.text('頻率區間'), findsNothing);
    expect(find.byKey(const Key('timetable-day-selector')), findsNothing);
    expect(find.byIcon(Icons.directions_bus), findsOneWidget);
    expect(find.text('關閉'), findsOneWidget);
  });

  testWidgets('each direction keeps its own last band', (tester) async {
    await _pumpDialog(tester, route: '1', direction: 0);
    expect(find.text('20:00 - 01:15'), findsOneWidget);
    expect(find.text('20:00 - 00:45'), findsNothing);

    await _pumpDialog(tester, route: '1', direction: 1);
    expect(find.text('20:00 - 00:45'), findsOneWidget);
    expect(find.text('20:00 - 01:15'), findsNothing);
  });

  testWidgets(
    'exact clocks stay clocks and the weekend suspension stays hidden on a weekday',
    (tester) async {
      await _pumpDialog(tester, route: '71S', direction: 0);
      expect(find.text('08:25'), findsOneWidget);
      expect(find.text('—'), findsWidgets);
      expect(find.text('服務暫停 / SERVIÇO SUSPENSO'), findsNothing);

      await _pumpDialog(tester, route: '71S', direction: 0, today: _saturday);
      expect(find.text('服務暫停 / SERVIÇO SUSPENSO'), findsOneWidget);
      expect(find.text('08:25'), findsNothing);
    },
  );

  testWidgets('the omitted clock follows today', (tester) async {
    await _pumpDialog(tester, route: '52', direction: 0, liveClock: true);
    final sections = DsatTimetable.sectionsFor('52', 0);
    final label = ServiceLabelI18n.translate(
      sections[timetableSectionIndexFor(sections, DateTime.now())].title,
      'zh',
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('timetable-day-selected')),
        matching: find.text(label),
      ),
      findsOneWidget,
    );
  });

  testWidgets('light theme keeps gold accents and dark band cards', (
    tester,
  ) async {
    await _pumpDialog(
      tester,
      route: '1A',
      direction: 0,
      brightness: Brightness.light,
    );

    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect(dialog.backgroundColor, Colors.white);
    expect(tester.widget<Text>(find.text('1A 時間表')).style?.color, Colors.black);
    expect(_bandDecoration(tester).color, const Color(0xFF2A2A2A));
    expect(
      tester
          .widget<Material>(
            find.byKey(const ValueKey('timetable-day-selected')),
          )
          .color,
      _gold,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('timetable-close')))
          .style
          ?.backgroundColor
          ?.resolve(const <WidgetState>{}),
      _gold,
    );
    expect(find.text('06:00 - 07:00'), findsOneWidget);
  });

  testWidgets('English uses translated section headers and the DSAT note', (
    tester,
  ) async {
    await _pumpDialog(tester, route: '1A', direction: 1, language: 'en');

    expect(find.text('1A Timetable'), findsOneWidget);
    expect(find.text('Service Hours'), findsNWidgets(5));
    expect(find.text('Frequency (mins)'), findsNWidgets(5));
    expect(find.text('Mon–Sat (except public holidays)'), findsOneWidget);
    expect(find.text('Sun & public holidays'), findsOneWidget);
    expect(
      find.text('Frequencies from official DSAT route information'),
      findsOneWidget,
    );
    expect(find.text('9 - 11'), findsOneWidget);
    expect(find.text('06:00 - 07:00'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('頻率區間'), findsNothing);
  });

  testWidgets('simplified Chinese and Portuguese use their own labels', (
    tester,
  ) async {
    await _pumpDialog(tester, route: '1A', direction: 0, language: 'zhHans');
    expect(find.text('1A 时间表'), findsOneWidget);
    expect(find.text('服务时间'), findsNWidgets(5));
    expect(find.text('班次(分钟)'), findsNWidgets(5));
    expect(find.text('星期一至六（公众假期除外）'), findsOneWidget);
    expect(find.text('星期日及公众假期'), findsOneWidget);
    expect(find.text('关闭'), findsOneWidget);
    expect(find.text('班次来自交通事务局（DSAT）官方路线资料'), findsOneWidget);

    await _pumpDialog(tester, route: '1A', direction: 0, language: 'pt');
    expect(find.text('1A Horário'), findsOneWidget);
    expect(find.text('Horário de Serviço'), findsNWidgets(5));
    expect(find.text('Frequência (min)'), findsNWidgets(5));
    expect(
      find.text('Seg. a Sáb.\n(exceto feriados públicos)'),
      findsOneWidget,
    );
    expect(find.text('Dom. e feriados públicos'), findsOneWidget);
    expect(find.text('Fechar'), findsOneWidget);
    expect(
      find.text('Frequências da informação oficial de carreiras da DSAT'),
      findsOneWidget,
    );
    expect(find.text('06:00 - 07:00'), findsOneWidget);
  });

  testWidgets('frequency label and minutes share the card right edge', (
    tester,
  ) async {
    await _expectFrequencyRow(tester, easyRead: false);
  });

  testWidgets('easy read mode keeps the frequency label on one line at 1.35x', (
    tester,
  ) async {
    await _expectFrequencyRow(tester, easyRead: true);
  });
}

/// Clock and frequency label stay on one line, next to each other, and share
/// the card's right edge. Covers every language at 320px and 390px.
Future<void> _expectFrequencyRow(
  WidgetTester tester, {
  required bool easyRead,
}) async {
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.view.devicePixelRatio = 1;

  for (final width in [320.0, 390.0]) {
    for (final language in ['zh', 'zhHans', 'pt', 'en']) {
      final label = AppTranslations.data[language]!['frequency_mins']!;
      final where = '$language ${width.toInt()}px easyRead=$easyRead';
      expect(label.contains('（'), isFalse, reason: where);
      expect(label.contains('）'), isFalse, reason: where);
      expect(RegExp(r'\(.*\)').hasMatch(label), isTrue, reason: where);
      if (language == 'zh') expect(label, '班次(分鐘)', reason: where);
      if (language == 'zhHans') expect(label, '班次(分钟)', reason: where);
      tester.view.physicalSize = Size(width, 844);
      await _pumpDialog(
        tester,
        route: '1A',
        direction: 0,
        language: language,
        easyRead: easyRead,
      );

      final card = find.byKey(const ValueKey('timetable-band-0'));
      final cardRect = tester.getRect(card);
      final labelFinder = find.descendant(of: card, matching: find.text(label));
      final valueFinder = find.descendant(
        of: card,
        matching: find.text('9 - 11'),
      );
      final iconFinder = find.descendant(
        of: card,
        matching: find.byIcon(Icons.schedule),
      );
      expect(labelFinder, findsOneWidget, reason: where);
      expect(valueFinder, findsOneWidget, reason: where);
      expect(iconFinder, findsOneWidget, reason: where);

      final heading = tester.widget<Text>(labelFinder);
      expect(heading.softWrap, isFalse, reason: where);
      expect(heading.maxLines, 1, reason: where);
      expect(heading.data, label, reason: where);
      expect(
        find.ancestor(of: labelFinder, matching: find.byType(FittedBox)),
        findsOneWidget,
        reason: where,
      );
      expect(
        _headingRow(tester, labelFinder).mainAxisSize,
        MainAxisSize.min,
        reason: where,
      );

      final paragraph = tester.renderObject<RenderParagraph>(labelFinder);
      final scale = easyRead ? EasyReadTheme.textScale : 1.0;
      expect(
        paragraph.textScaler.scale(1),
        closeTo(scale, 0.01),
        reason: where,
      );

      final labelRect = tester.getRect(labelFinder);
      final valueRect = tester.getRect(valueFinder);
      final iconRect = tester.getRect(iconFinder);
      final edge = cardRect.right - 14;
      expect(labelRect.right, closeTo(edge, 1.5), reason: where);
      expect(valueRect.right, closeTo(edge, 1.5), reason: where);
      expect(labelRect.right, closeTo(valueRect.right, 1.5), reason: where);

      final gap = labelRect.left - iconRect.right;
      expect(gap, inInclusiveRange(0.5, 5), reason: '$where gap=$gap');
      expect(
        (iconRect.center.dy - labelRect.center.dy).abs(),
        lessThan(1.5),
        reason: where,
      );

      final unscaledLine =
          heading.style!.fontSize! * (heading.style!.height ?? 1);
      final oneLine = unscaledLine * scale;
      // The paragraph itself is one full line. FittedBox may shrink the paint.
      expect(paragraph.size.height, closeTo(oneLine, 1.5), reason: where);
      expect(labelRect.height, lessThanOrEqualTo(oneLine + 1.5), reason: where);
      if (easyRead) {
        // 1.35x text stays taller than the normal label, even if the row
        // scales down a little on a 320px-wide card.
        expect(
          labelRect.height,
          greaterThan(unscaledLine),
          reason: '$where height=${labelRect.height} normal=$unscaledLine',
        );
      }
      if (!easyRead || width >= 390) {
        expect(
          labelRect.height,
          closeTo(oneLine, 1.5),
          reason: '$where height=${labelRect.height} line=$oneLine',
        );
      }

      final timeRect = tester.getRect(
        find.descendant(of: card, matching: find.textContaining(':')),
      );
      expect(
        timeRect.right,
        lessThanOrEqualTo(iconRect.left + 1),
        reason: where,
      );
    }
  }
}

Row _headingRow(WidgetTester tester, Finder labelFinder) {
  Row? heading;
  tester.element(labelFinder).visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is Row) {
      heading = widget;
      return false;
    }
    return true;
  });
  expect(heading, isNotNull);
  return heading!;
}
