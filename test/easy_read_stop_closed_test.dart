import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:macau_bus_app/constants/app_translations.dart';
import 'package:macau_bus_app/controllers/background_controller.dart';
import 'package:macau_bus_app/controllers/bus_controller.dart';
import 'package:macau_bus_app/controllers/easy_read_mode_controller.dart';
import 'package:macau_bus_app/controllers/language_controller.dart';
import 'package:macau_bus_app/controllers/location_controller.dart';
import 'package:macau_bus_app/controllers/navigation_controller.dart';
import 'package:macau_bus_app/models/bus_stop.dart';
import 'package:macau_bus_app/services/open_data_config.dart';
import 'package:macau_bus_app/theme/easy_read_theme.dart';
import 'package:macau_bus_app/views/screens/bus_route_screen.dart';
import 'package:macau_bus_app/views/widgets/blinking_warning_icon.dart';
import 'package:macau_bus_app/views/widgets/route_liquid_glass_nav.dart';

BusStop _stop(int seq, {bool closed = false, String? zhHans, String? pt, String? en}) {
  final zh = '站$seq';
  return BusStop(
    seq: seq,
    name: zh,
    nameZh: zh,
    nameZhHans: zhHans ?? '站$seq',
    namePt: pt ?? 'Paragem $seq',
    nameEn: en ?? 'Stop $seq',
    code: 'M$seq/2',
    lat: 22.2,
    lng: 113.55,
    hasAlert: closed,
  );
}

Future<void> _pumpStation(
  WidgetTester tester, {
  required String langCode,
  required Size size,
  double safeBottom = 34,
  int stopCount = 14,
  int closedSeq = 14,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.viewPadding = FakeViewPadding(bottom: safeBottom);
  tester.view.padding = FakeViewPadding(bottom: safeBottom);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewPadding);
  addTearDown(tester.view.resetPadding);

  SharedPreferences.setMockInitialValues({'language_code': langCode});
  OpenDataConfig.instance.debugApply(
    configRealtime: false,
    configRouteNotices: true,
  );
  final lang = LanguageController();
  final bus = BusController();
  bus.setRoute('3');
  bus.stopsList = [
    for (var i = 1; i <= stopCount; i++) _stop(i, closed: i == closedSeq),
  ];
  bus.selectedStopSeq = 1;

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<BusController>.value(value: bus),
        ChangeNotifierProvider<LanguageController>.value(value: lang),
        ChangeNotifierProvider(create: (_) => LocationController()),
        ChangeNotifierProvider(create: (_) => BackgroundController()),
        ChangeNotifierProvider(create: (_) => NavigationController()),
        ChangeNotifierProvider(create: (_) => EasyReadModeController.fixed(true)),
      ],
      child: MaterialApp(
        theme: ThemeData(brightness: Brightness.light, platform: TargetPlatform.iOS),
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(textScaler: TextScaler.linear(EasyReadTheme.textScale)),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const BusRouteScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    bus.dispose();
    lang.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OpenDataConfig.instance.debugReset();
  });

  tearDown(OpenDataConfig.instance.debugReset);

  testWidgets('closure line follows the active language', (tester) async {
    const expected = {
      'zh': '此站暫停停靠',
      'zhHans': '此站暂停停靠',
      'en': 'Stop closed',
      'pt': 'Paragem suspensa',
    };
    const locales = {
      'zh': Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      'zhHans': Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      'en': Locale('en'),
      'pt': Locale('pt'),
    };

    for (final entry in expected.entries) {
      await _pumpStation(
        tester,
        langCode: entry.key,
        size: const Size(390, 800),
        stopCount: 3,
        closedSeq: 2,
      );
      expect(find.text('此站暫停停靠'), entry.key == 'zh' ? findsOneWidget : findsNothing);
      expect(find.text(entry.value), findsOneWidget);
      expect(find.text(AppTranslations.data[entry.key]!['easy_read_stop_closed']!), findsOneWidget);
      final text = tester.widget<Text>(find.text(entry.value));
      expect(text.locale, locales[entry.key]);
      expect(text.softWrap, isTrue);
    }
  });

  testWidgets('closure line clears the bottom nav and stays beside the bell', (tester) async {
    const size = Size(320, 640);
    const safeBottom = 34.0;
    await _pumpStation(tester, langCode: 'zhHans', size: size, safeBottom: safeBottom);

    final reserve = RouteLiquidGlassNavStyle.easyReadBarHeight +
        RouteLiquidGlassNavStyle.barBottomOffset(safeBottom, ios: true);
    final navTop = size.height - reserve;
    final list = tester.widget<ListView>(find.byType(ListView));
    expect(list.padding!.resolve(TextDirection.ltr).bottom, greaterThan(reserve));

    final position = list.controller!.position;
    for (var i = 0; i < 8 && position.pixels < position.maxScrollExtent - 1; i++) {
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
    }

    expect(find.text('此站暂停停靠'), findsOneWidget);
    expect(find.text('此站暫停停靠'), findsNothing);

    final textRect = tester.getRect(find.text('此站暂停停靠'));
    expect(textRect.bottom, lessThanOrEqualTo(navTop));
    expect(textRect.left, greaterThanOrEqualTo(0));
    expect(textRect.right, lessThanOrEqualTo(size.width));

    final iconRect = tester.getRect(find.byType(BlinkingWarningIcon));
    expect(textRect.overlaps(iconRect), isFalse);
  });

  testWidgets('portuguese closure line wraps inside a narrow row', (tester) async {
    await _pumpStation(
      tester,
      langCode: 'pt',
      size: const Size(320, 700),
      safeBottom: 34,
      stopCount: 3,
      closedSeq: 2,
    );
    expect(find.text('Paragem suspensa'), findsOneWidget);
    final textRect = tester.getRect(find.text('Paragem suspensa'));
    expect(textRect.right, lessThanOrEqualTo(320));
    expect(textRect.left, greaterThanOrEqualTo(0));
    final iconRect = tester.getRect(find.byType(BlinkingWarningIcon));
    expect(textRect.overlaps(iconRect), isFalse);
  });
}
