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
  addTearDown(() {
    lang.dispose();
    bus.dispose();
    purchase.dispose();
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
        ChangeNotifierProvider(create: (_) => EasyReadModeController.fixed(easyRead)),
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
      },
    );
  }
}
