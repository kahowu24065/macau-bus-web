import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:macau_bus_app/controllers/background_controller.dart';
import 'package:macau_bus_app/controllers/bus_controller.dart';
import 'package:macau_bus_app/controllers/easy_read_mode_controller.dart';
import 'package:macau_bus_app/controllers/language_controller.dart';
import 'package:macau_bus_app/controllers/location_controller.dart';
import 'package:macau_bus_app/controllers/navigation_controller.dart';
import 'package:macau_bus_app/controllers/purchase_controller.dart';
import 'package:macau_bus_app/controllers/theme_controller.dart';
import 'package:macau_bus_app/theme/easy_read_theme.dart';
import 'package:macau_bus_app/views/screens/settings_screen.dart';
import 'package:macau_bus_app/views/widgets/easy_read_tap_haptics.dart';
import 'package:macau_bus_app/views/widgets/preserve_chrome.dart';

const _legalGrey = Color(0xFF8A8A93);

Future<void> _pumpSettings(WidgetTester tester, {required bool easyRead}) async {
  SharedPreferences.setMockInitialValues({'language_code': 'zh'});
  final lang = LanguageController();
  final bus = BusController();
  final purchase = PurchaseController();
  final easyReadCtrl = EasyReadModeController.fixed(easyRead);
  addTearDown(() {
    lang.dispose();
    bus.dispose();
    purchase.dispose();
    easyReadCtrl.dispose();
  });

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeController()),
        ChangeNotifierProvider(create: (_) => LocationController()),
        ChangeNotifierProvider<BusController>.value(value: bus),
        ChangeNotifierProvider<PurchaseController>.value(value: purchase),
        ChangeNotifierProvider(create: (_) => BackgroundController()),
        ChangeNotifierProvider<LanguageController>.value(value: lang),
        ChangeNotifierProvider(create: (_) => NavigationController()),
        ChangeNotifierProvider<EasyReadModeController>.value(value: easyReadCtrl),
      ],
      child: MaterialApp(
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
        home: const SettingsScreen(),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('arrival read-aloud switch stays visible and follows each mode', (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpSettings(tester, easyRead: false);
    expect(find.text('讀出到站資訊'), findsOneWidget);
    final easy = tester.getTopLeft(find.text('易讀模式'));
    final speech = tester.getTopLeft(find.text('讀出到站資訊'));
    final theme = tester.getTopLeft(find.text('切換日夜模式'));
    expect(speech.dy, greaterThan(easy.dy));
    expect(theme.dy, greaterThan(speech.dy));

    CupertinoSwitch switchFor(String title) {
      final tile = find.ancestor(of: find.text(title), matching: find.byType(ListTile)).first;
      return tester.widget<CupertinoSwitch>(
        find.descendant(of: tile, matching: find.byType(CupertinoSwitch)),
      );
    }

    Future<void> tapSwitch(String title) async {
      final tile = find.ancestor(of: find.text(title), matching: find.byType(ListTile)).first;
      await tester.ensureVisible(tile);
      await tester.pump();
      await tester.tap(find.descendant(of: tile, matching: find.byType(CupertinoSwitch)));
      await tester.pump();
    }

    final ctrl = tester.element(find.byType(SettingsScreen)).read<EasyReadModeController>();
    expect(ctrl.speakArrivals, isFalse);
    expect(switchFor('讀出到站資訊').value, isFalse);

    await tapSwitch('易讀模式');
    expect(ctrl.enabled, isTrue);
    expect(ctrl.speakArrivals, isTrue);
    expect(switchFor('讀出到站資訊').value, isTrue);

    await tapSwitch('讀出到站資訊');
    expect(ctrl.speakArrivals, isFalse);

    await tapSwitch('易讀模式');
    expect(ctrl.enabled, isFalse);
    expect(ctrl.speakArrivals, isFalse);

    await tapSwitch('讀出到站資訊');
    expect(ctrl.speakArrivals, isTrue);

    await tapSwitch('易讀模式');
    expect(ctrl.enabled, isTrue);
    expect(ctrl.speakArrivals, isFalse);
  });

  testWidgets('speech language sits under the readout switch and stays hidden when it is off', (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpSettings(tester, easyRead: false);
    expect(find.text('讀出語言'), findsNothing);

    Future<void> tapSwitch(String title) async {
      final tile = find.ancestor(of: find.text(title), matching: find.byType(ListTile)).first;
      await tester.ensureVisible(tile);
      await tester.pump();
      await tester.tap(find.descendant(of: tile, matching: find.byType(CupertinoSwitch)));
      await tester.pump();
    }

    await tapSwitch('讀出到站資訊');
    expect(find.text('讀出語言'), findsOneWidget);
    expect(find.text('廣東話'), findsOneWidget);
    final readout = tester.getTopLeft(find.text('讀出到站資訊'));
    final language = tester.getTopLeft(find.text('讀出語言'));
    final theme = tester.getTopLeft(find.text('切換日夜模式'));
    expect(language.dy, greaterThan(readout.dy));
    expect(theme.dy, greaterThan(language.dy));
    final normalTitle = tester.widget<Text>(find.text('讀出語言'));
    expect(normalTitle.style?.fontSize, 15);
    expect(normalTitle.style?.fontWeight, FontWeight.w500);

    final tile = find.ancestor(of: find.text('讀出語言'), matching: find.byType(ListTile)).first;
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.widgetWithText(CupertinoActionSheetAction, '普通話'));
    await tester.pumpAndSettle();

    expect(find.text('普通話'), findsOneWidget);
    expect(find.text('廣東話'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('speech_language'), 'zhHans');

    await tapSwitch('讀出到站資訊');
    expect(find.text('讀出語言'), findsNothing);
    expect(find.text('普通話'), findsNothing);

    await tapSwitch('讀出到站資訊');
    expect(find.text('普通話'), findsOneWidget);

    await tapSwitch('易讀模式');
    final easyTitle = tester.widget<Text>(find.text('讀出語言'));
    expect(easyTitle.style?.fontSize, 15);
    expect(easyTitle.style?.fontWeight, FontWeight.w700);
    expect(tester.widget<Text>(find.text('普通話')).style?.fontSize, 14);
  });

  for (final easyRead in [false, true]) {
    testWidgets(
      'member legal links stay grey and unlined when easy read is $easyRead',
      (tester) async {
        await _pumpSettings(tester, easyRead: easyRead);

        expect(find.text('使用條款 (EULA)'), findsOneWidget);
        expect(find.text('私隱權政策'), findsOneWidget);
        expect(find.text('關於我們'), findsOneWidget);
        expect(find.text('免責聲明'), findsOneWidget);

        for (final label in ['使用條款 (EULA)', '私隱權政策']) {
          final text = tester.widget<Text>(find.text(label));
          expect(text.style?.color, _legalGrey);
          expect(text.style?.decoration, TextDecoration.none);
        }

        final description = tester.widget<Text>(find.text('字同按鈕會大啲。'));
        expect(description.style?.color, _legalGrey);
        expect(description.style?.fontSize, 13);
      },
    );
  }
}
