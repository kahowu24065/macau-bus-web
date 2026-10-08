import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:macau_bus_app/constants/app_translations.dart';
import 'package:macau_bus_app/controllers/background_controller.dart';
import 'package:macau_bus_app/controllers/bus_controller.dart';
import 'package:macau_bus_app/controllers/easy_read_mode_controller.dart';
import 'package:macau_bus_app/controllers/keyboard_controller.dart';
import 'package:macau_bus_app/controllers/language_controller.dart';
import 'package:macau_bus_app/controllers/location_controller.dart';
import 'package:macau_bus_app/controllers/navigation_controller.dart';
import 'package:latlong2/latlong.dart';
import 'package:macau_bus_app/models/bus_stop.dart';
import 'package:macau_bus_app/theme/easy_read_theme.dart';
import 'package:macau_bus_app/views/screens/bus_route_screen.dart';
import 'package:macau_bus_app/views/screens/dashboard_screen.dart';
import 'package:macau_bus_app/views/widgets/easy_read_tap_haptics.dart';
import 'package:macau_bus_app/views/widgets/preserve_chrome.dart';

class _QuietLocation extends LocationController {
  @override
  Future<void> toggleLocationTracking(Function(LatLng) onLocationUpdated) async {}
}

class _OfflineHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    throw const SocketException('widget test is offline');
  }
}

String _tr(String lang, String key) => AppTranslations.data[lang]![key]!;

BusStop _stop({
  required int seq,
  required String zh,
  required String zhHans,
  required String pt,
  required String en,
  bool hasAlert = false,
}) {
  return BusStop(
    seq: seq,
    name: zh,
    nameZh: zh,
    nameZhHans: zhHans,
    namePt: pt,
    nameEn: en,
    code: 'M$seq/2',
    lat: 22.2,
    lng: 113.55,
    hasAlert: hasAlert,
  );
}

Text _textMatching(WidgetTester tester, bool Function(String data) match) {
  final finder = find.byWidgetPredicate((widget) {
    if (widget is! Text || widget.data == null) return false;
    return match(widget.data!);
  });
  expect(finder, findsOneWidget);
  return tester.widget<Text>(finder);
}

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
  for (final name in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']) {
    final bytes = await File('${fonts.path}/$name').readAsBytes();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

Widget _app({
  required bool easyRead,
  required Widget home,
  Brightness brightness = Brightness.dark,
}) {
  return MaterialApp(
    theme: ThemeData(brightness: brightness, fontFamily: 'Roboto'),
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
            data: EasyReadTheme.apply(base),
            child: EasyReadTapHaptics(child: child),
          ),
        ),
      );
    },
    home: home,
  );
}

Future<void> _pumpStation(
  WidgetTester tester, {
  required String langCode,
  required bool easyRead,
  String route = '3',
  Size size = const Size(320, 568),
  bool alert = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({'language_code': langCode});
  final lang = LanguageController();
  await lang.changeLanguage(langCode);
  final bus = BusController();
  bus.setRoute(route);
  bus.stopsList = [
    _stop(
      seq: 12,
      zh: '外港客運碼頭北',
      zhHans: '外港客运码头北',
      pt: 'Terminal Marítimo do Porto Exterior Norte',
      en: 'Outer Harbour Ferry Terminal North',
      hasAlert: alert,
    ),
    _stop(
      seq: 1,
      zh: '媽閣',
      zhHans: '妈阁',
      pt: 'Barra',
      en: 'Barra',
      hasAlert: alert,
    ),
  ];
  bus.selectedStopSeq = null;
  addTearDown(lang.dispose);
  addTearDown(bus.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<BusController>.value(value: bus),
        ChangeNotifierProvider<LanguageController>.value(value: lang),
        ChangeNotifierProvider<LocationController>(create: (_) => _QuietLocation()),
        ChangeNotifierProvider(create: (_) => BackgroundController()),
        ChangeNotifierProvider(create: (_) => NavigationController()),
        ChangeNotifierProvider<EasyReadModeController>.value(
          value: EasyReadModeController.fixed(easyRead),
        ),
      ],
      child: _app(easyRead: easyRead, home: const BusRouteScreen()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _pumpSearch(
  WidgetTester tester, {
  required bool easyRead,
  Size size = const Size(390, 844),
  Brightness brightness = Brightness.dark,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({'language_code': 'zh'});
  final lang = LanguageController();
  final bus = BusController();
  final keyboard = KeyboardController();
  keyboard.openKeyboard();
  keyboard.routeController.text = '1';
  addTearDown(lang.dispose);
  addTearDown(bus.dispose);
  addTearDown(keyboard.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<BusController>.value(value: bus),
        ChangeNotifierProvider<LanguageController>.value(value: lang),
        ChangeNotifierProvider<LocationController>(create: (_) => _QuietLocation()),
        ChangeNotifierProvider(create: (_) => BackgroundController()),
        ChangeNotifierProvider(create: (_) => NavigationController()),
        ChangeNotifierProvider<KeyboardController>.value(value: keyboard),
        ChangeNotifierProvider(create: (_) => EasyReadModeController.fixed(easyRead)),
      ],
      child: _app(easyRead: easyRead, brightness: brightness, home: const DashboardScreen()),
    ),
  );
  // First frame anchors the menu; the following frame paints it.
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final previousHttp = HttpOverrides.current;

  setUpAll(_loadRoboto);

  setUp(() {
    HttpOverrides.global = _OfflineHttpOverrides();
    SharedPreferences.setMockInitialValues({'language_code': 'zh'});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'),
      (call) async {
        switch (call.method) {
          case 'checkPermission':
          case 'requestPermission':
            return 0;
          case 'isLocationServiceEnabled':
            return false;
          default:
            return null;
        }
      },
    );
  });

  tearDown(() {
    HttpOverrides.global = previousHttp;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'),
      null,
    );
  });

  for (final easyRead in [false, true]) {
    testWidgets(
      'route suggestions sit just under the search field when easy read is $easyRead',
      (tester) async {
        await _pumpSearch(tester, easyRead: easyRead);

        expect(find.byKey(const Key('route-suggestions')), findsOneWidget);
        final field = tester.getRect(find.byType(TextField));
        final menu = tester.getRect(find.byKey(const Key('route-suggestions')));
        final gap = menu.top - field.bottom;
        expect(gap, greaterThanOrEqualTo(4), reason: 'gap=$gap');
        expect(gap, lessThanOrEqualTo(12), reason: 'gap=$gap');
      },
    );
  }

  testWidgets('easy read fare button stays clear of the route number', (tester) async {
    for (final width in [320.0, 390.0]) {
      for (final language in ['zh', 'zhHans', 'pt', 'en']) {
        final label = _tr(language, 'fare_table');
        final where = '$language ${width.toInt()}px';
        await _pumpStation(
          tester,
          langCode: language,
          easyRead: true,
          route: '25BS',
          size: Size(width, 844),
        );

        final fare = find.text(label);
        expect(fare, findsOneWidget, reason: where);
        final fareText = tester.widget<Text>(fare);
        expect(fareText.softWrap, isFalse, reason: where);
        expect(fareText.maxLines, 1, reason: where);
        expect(fareText.style?.fontSize, 18, reason: where);
        expect(tester.widget<Icon>(find.byIcon(Icons.monetization_on)).size, 22, reason: where);

        final routeRect = tester.getRect(find.text('25BS'));
        final fareRect = tester.getRect(fare);
        expect(fareRect.left - routeRect.right, greaterThanOrEqualTo(7), reason: '$where gap=${fareRect.left - routeRect.right}');
        expect(fareRect.right, lessThanOrEqualTo(width - 19), reason: where);
        expect(fareRect.top, greaterThanOrEqualTo(routeRect.top), reason: where);
        expect(fareRect.bottom, lessThanOrEqualTo(routeRect.bottom + 1), reason: where);
        expect(fareRect.height, lessThan(28), reason: where);
      }
    }

    await _pumpStation(
      tester,
      langCode: 'pt',
      easyRead: false,
      route: '25BS',
      size: const Size(320, 844),
    );
    final normal = tester.widget<Text>(find.text('Tarifas'));
    expect(normal.style?.fontSize, 13);
    expect(tester.widget<Icon>(find.byIcon(Icons.monetization_on)).size, 16);
    final routeRect = tester.getRect(find.text('25BS'));
    final fareRect = tester.getRect(find.text('Tarifas'));
    expect(fareRect.left, greaterThan(routeRect.right));
  });

  testWidgets('easy read more button matches the search title colour', (tester) async {
    for (final brightness in [Brightness.dark, Brightness.light]) {
      await _pumpSearch(tester, easyRead: true, brightness: brightness);
      final title = tester.widget<Text>(find.text('尋找路線'));
      final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '更多'));
      final background = button.style?.backgroundColor?.resolve(const <WidgetState>{});
      expect(title.style?.color, Colors.amber.shade600, reason: '$brightness');
      expect(background, title.style?.color, reason: '$brightness');
    }
  });

  testWidgets('easy read keeps More on the search page only', (tester) async {
    await _pumpSearch(tester, easyRead: true, size: const Size(320, 568));
    expect(find.text('更多'), findsOneWidget);

    await _pumpStation(tester, langCode: 'zh', easyRead: true);
    expect(find.text('更多'), findsNothing);
    expect(find.text('Mais'), findsNothing);
    expect(find.text('More'), findsNothing);
  });

  testWidgets('normal station page keeps the original stop and button sizes', (tester) async {
    await _pumpStation(
      tester,
      langCode: 'en',
      easyRead: false,
      size: const Size(390, 844),
    );

    expect(find.text('More'), findsNothing);
    final direction = _textMatching(tester, (data) => data.startsWith('To '));
    expect(direction.style?.fontSize, 15);
    final stop = _textMatching(tester, (data) => data.contains('Barra (M1/2)'));
    expect(stop.style?.fontSize, 16);
    final timetable = _textMatching(tester, (data) => data.replaceAll('\n', '') == 'Timetable');
    expect(timetable.style?.fontSize, 11);
  });

  testWidgets('easy read station info matches the header caption size', (tester) async {
    await _pumpStation(
      tester,
      langCode: 'zh',
      easyRead: true,
      size: const Size(390, 844),
      alert: true,
    );

    final info = _textMatching(tester, (data) => data == '站點資訊：');
    final caption = _textMatching(tester, (data) => data == '對頭線');
    expect(info.style?.fontSize, 14);
    expect(caption.style?.fontSize, info.style?.fontSize);
    expect(
      _textMatching(tester, (data) => data.startsWith('12. ')).style?.fontSize,
      info.style?.fontSize,
    );
    expect(
      _textMatching(tester, (data) => data == '、').style?.fontSize,
      info.style?.fontSize,
    );
    expect(find.text('此站暫時停靠'), findsNWidgets(2));
    expect(find.text('此站暫停停靠'), findsNothing);
  });

  testWidgets('normal station info stays at the 1.0.33 size', (tester) async {
    await _pumpStation(
      tester,
      langCode: 'en',
      easyRead: false,
      size: const Size(390, 844),
      alert: true,
    );

    expect(_textMatching(tester, (data) => data == 'Stop Info:').style?.fontSize, 13);
    expect(
      _textMatching(tester, (data) => data.startsWith('12. ')).style?.fontSize,
      13,
    );
    expect(_textMatching(tester, (data) => data == '、').style?.fontSize, 13);
    expect(
      _textMatching(tester, (data) => data == 'Timetable').style?.fontSize,
      11,
    );
    expect(find.text('Temporary stop'), findsNothing);
  });

  for (final lang in ['zh', 'zhHans', 'pt', 'en']) {
    for (final size in [const Size(320, 568), const Size(390, 844)]) {
      testWidgets(
        'easy read station header and stop text fit ($lang ${size.width.toInt()}px)',
        (tester) async {
          await _pumpStation(
            tester,
            langCode: lang,
            easyRead: true,
            size: size,
          );

          expect(find.text(_tr(lang, 'more_options')), findsNothing);

          final direction = _textMatching(
            tester,
            (data) => data.startsWith('${_tr(lang, 'direction_to')} '),
          );
          expect(direction.style?.fontSize, 18);

          final sample = switch (lang) {
            'zh' => '媽閣 (M1/2)',
            'zhHans' => '妈阁 (M1/2)',
            'pt' => 'Barra (M1/2)',
            _ => 'Barra (M1/2)',
          };
          final stop = _textMatching(tester, (data) => data.contains(sample));
          final row = _textMatching(tester, (data) => data.contains('(M12/2)'));
          for (final caption in [stop, row]) {
            final finder = find.text(caption.data!);
            final rect = tester.getRect(finder);
            expect(rect.right, lessThanOrEqualTo(size.width + 0.5), reason: caption.data);
            final tile = find.ancestor(of: finder, matching: find.byType(InkWell)).first;
            final bell = find.descendant(of: tile, matching: find.byType(IconButton));
            expect(rect.right, lessThanOrEqualTo(tester.getRect(bell).left + 0.5), reason: caption.data);
            final seq = find.descendant(
              of: tile,
              matching: find.byWidgetPredicate((widget) {
                return widget is Text && RegExp(r'^\d+\.$').hasMatch(widget.data ?? '');
              }),
            );
            final seqText = tester.widget<Text>(seq);
            expect(seqText.style?.fontSize, caption.style?.fontSize, reason: caption.data);
            expect(tester.getRect(seq).right, lessThanOrEqualTo(rect.left + 0.5), reason: caption.data);
          }
          final rowFinder = find.text(row.data!);

          final labels = <Rect>[];
          const headerSize = 14.0;
          final stopSize = 19 * EasyReadTheme.textScale;
          expect(stop.style?.fontSize, stopSize, reason: '$lang stop');
          expect(row.style?.fontSize, stopSize, reason: '$lang row');
          for (final key in ['swap_direction', 'location', 'timetable', 'tab_map', 'favorite']) {
            final plain = _tr(lang, key);
            final label = _textMatching(tester, (data) => data == plain);
            final labelFinder = find.text(plain);
            expect(label.maxLines, 1, reason: '$lang $plain');
            expect(label.softWrap, isFalse, reason: '$lang $plain');
            expect(label.style?.fontSize, headerSize, reason: '$lang $plain');
            final column = find.ancestor(of: labelFinder, matching: find.byType(Column)).first;
            final icon = tester.widget<Icon>(
              find.descendant(of: column, matching: find.byType(Icon)),
            );
            expect(icon.size, 24, reason: '$lang $plain');
            final paintedStop = MediaQuery.textScalerOf(tester.element(find.byWidget(stop)))
                .scale(stop.style!.fontSize!);
            final paintedRow = MediaQuery.textScalerOf(tester.element(rowFinder))
                .scale(row.style!.fontSize!);
            expect(paintedStop, closeTo(stopSize, 0.01), reason: '$lang stop paint');
            expect(paintedRow, closeTo(stopSize, 0.01), reason: '$lang row paint');
            final rect = tester.getRect(labelFinder);
            expect(rect.left, greaterThanOrEqualTo(-0.5), reason: '$lang $plain $rect');
            expect(rect.right, lessThanOrEqualTo(size.width + 0.5), reason: '$lang $plain $rect');
            expect(rect.top, greaterThanOrEqualTo(0), reason: '$lang $plain $rect');
            expect(rect.bottom, lessThan(size.height), reason: '$lang $plain $rect');
            labels.add(rect);
          }
          labels.sort((a, b) => a.left.compareTo(b.left));
          for (var i = 0; i < labels.length - 1; i++) {
            expect(
              labels[i].right,
              lessThanOrEqualTo(labels[i + 1].left + 0.5),
              reason: '$lang overlap ${labels[i]} ${labels[i + 1]}',
            );
          }
        },
      );
    }
  }
}
