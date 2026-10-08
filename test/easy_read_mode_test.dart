import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:macau_bus_app/constants/app_translations.dart';
import 'package:macau_bus_app/controllers/easy_read_mode_controller.dart';
import 'package:macau_bus_app/controllers/language_controller.dart';
import 'package:macau_bus_app/services/arrival_speaker.dart';
import 'package:macau_bus_app/theme/easy_read_theme.dart';
import 'package:macau_bus_app/utils/easy_read_arrival.dart';
import 'package:macau_bus_app/views/screens/easy_read_more_screen.dart';
import 'package:macau_bus_app/views/screens/home_screen.dart';

String _tr(String lang, String key) =>
    AppTranslations.data[lang]?[key] ?? AppTranslations.data['zh']?[key] ?? key;

class _FakeSpeech implements SpeechEngine {
  final List<String> calls = [];
  bool failLanguages = false;

  @override
  Future<void> prepareIos() async {}

  @override
  Future<void> setLanguage(String language) async {
    calls.add('lang:$language');
    if (failLanguages) throw StateError('no voice');
  }

  @override
  Future<void> setSpeechRate(double rate) async {
    calls.add('rate:$rate');
  }

  @override
  Future<void> speak(String text) async {
    calls.add('say:$text');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('easy read mode defaults off and persists', () async {
    final first = EasyReadModeController();
    await first.ready;
    expect(first.enabled, isFalse);

    await first.setEnabled(true);
    final second = EasyReadModeController();
    await second.ready;
    expect(second.enabled, isTrue);
  });

  test('fixed controller does not read preferences', () async {
    SharedPreferences.setMockInitialValues({'easy_read_mode': true});
    final fixed = EasyReadModeController.fixed(false);
    await fixed.ready;
    expect(fixed.enabled, isFalse);
  });

  test('translations include easy read mode in all four languages', () {
    const keys = [
      'easy_read_mode',
      'easy_read_mode_desc',
      'easy_read_eta_mins',
      'easy_read_arriving_next',
      'easy_read_arriving_soon',
      'more_options',
      'easy_read_stop_closed',
      'easy_read_diversion',
      'easy_read_no_diversion',
      'easy_read_pick_route',
      'easy_read_list_empty',
    ];
    for (final lang in ['zh', 'zhHans', 'pt', 'en']) {
      for (final key in keys) {
        expect(
          AppTranslations.data[lang]![key],
          isNotNull,
          reason: '$lang.$key',
        );
        expect(AppTranslations.data[lang]![key]!.trim(), isNotEmpty);
      }
    }
    expect(AppTranslations.data['zh']!['easy_read_mode'], '易讀模式');
    expect(AppTranslations.data['zh']!['more_options'], '更多');
    expect(AppTranslations.data['zh']!['easy_read_eta_mins'], '@mins 分鐘後到');
    expect(AppTranslations.data['zh']!['easy_read_mode_desc'], contains('\n'));
    expect(AppTranslations.data['en']!['easy_read_mode'], 'Easy Read Mode');
    expect(
      AppTranslations.data['pt']!['easy_read_mode'],
      'Modo de Leitura Fácil',
    );
    expect(AppTranslations.data['pt']!['more_options'], 'Mais');
    expect(AppTranslations.data['zhHans']!['easy_read_mode'], '易读模式');
  });

  test('arrival wording keeps next-stop and arriving-soon logic', () {
    String zh(String key) => _tr('zh', key);

    expect(
      approachingStatus(
        easyRead: false,
        stopsAway: 2,
        estimatedMins: 4,
        tr: zh,
      ),
      '尚有 2 站 (約 4 分鐘)',
    );
    expect(
      approachingStatus(
        easyRead: false,
        stopsAway: 1,
        estimatedMins: 5,
        tr: zh,
      ),
      '下站到達 (約 5 分鐘)',
    );
    expect(
      approachingStatus(
        easyRead: false,
        stopsAway: 1,
        estimatedMins: 0,
        tr: zh,
      ),
      '下站到達',
    );
    expect(
      approachingStatus(
        easyRead: false,
        stopsAway: 0,
        estimatedMins: 0,
        tr: zh,
      ),
      '即將到站 / 到站中',
    );

    expect(
      approachingStatus(easyRead: true, stopsAway: 2, estimatedMins: 4, tr: zh),
      '4 分鐘後到',
    );
    expect(
      approachingStatus(easyRead: true, stopsAway: 1, estimatedMins: 5, tr: zh),
      '5 分鐘後到',
    );
    expect(
      approachingStatus(easyRead: true, stopsAway: 1, estimatedMins: 0, tr: zh),
      '下一站到達',
    );
    expect(
      approachingStatus(easyRead: true, stopsAway: 0, estimatedMins: 0, tr: zh),
      '即將到站',
    );
    expect(
      presentArrivalStatus(easyRead: true, status: zh('service_ended'), tr: zh),
      '本日服務已結束',
    );
    expect(
      approachingStatus(
        easyRead: true,
        stopsAway: 3,
        estimatedMins: 8,
        tr: (key) => _tr('en', key),
      ),
      'In 8 min',
    );
    expect(
      approachingStatus(
        easyRead: true,
        stopsAway: 0,
        estimatedMins: 0,
        tr: (key) => _tr('pt', key),
      ),
      'A chegar',
    );
  });

  test('text scale undo restores the size under the header', () {
    expect(
      EasyReadTheme.undoTextScale(const TextScaler.linear(1.35)).scale(1),
      closeTo(1, 0.001),
    );
    expect(
      EasyReadTheme.undoTextScale(const TextScaler.linear(1.2 * 1.35)).scale(1),
      closeTo(1.2, 0.001),
    );
  });

  test('contrast lifts grey and keeps saturated colours in both themes', () {
    expect(
      EasyReadTheme.lift(Colors.grey.shade500, Brightness.light),
      EasyReadTheme.lightForeground,
    );
    expect(
      EasyReadTheme.lift(Colors.grey.shade500, Brightness.dark),
      Colors.white,
    );
    expect(EasyReadTheme.lift(Colors.white70, Brightness.dark), Colors.white);
    expect(
      EasyReadTheme.lift(Colors.black54, Brightness.light),
      EasyReadTheme.lightForeground,
    );
    expect(EasyReadTheme.lift(Colors.amber, Brightness.light), Colors.amber);
    expect(EasyReadTheme.lift(Colors.black, Brightness.light), Colors.black);
    expect(EasyReadTheme.lift(Colors.white, Brightness.dark), Colors.white);

    final light = EasyReadTheme.apply(ThemeData.light());
    final dark = EasyReadTheme.apply(ThemeData.dark());
    expect(
      light.textButtonTheme.style?.minimumSize?.resolve({}),
      const Size(72, 56),
    );
    expect(dark.colorScheme.onSurface, Colors.white);
    expect(light.colorScheme.onSurface, EasyReadTheme.lightForeground);
    expect(light.textTheme.bodyMedium?.fontWeight, FontWeight.w700);
    expect(dark.textTheme.bodyMedium?.fontWeight, FontWeight.w700);
  });

  test('easy read mode hides every ad slot except settings', () {
    bool show({
      required int selectedIndex,
      bool easyReadMode = true,
      bool isPro = false,
    }) {
      return showHomeBannerSlot(
        isWeb: false,
        isPro: isPro,
        showMapView: false,
        selectedIndex: selectedIndex,
        isPlanningRoute: false,
        easyReadMode: easyReadMode,
      );
    }

    expect(show(selectedIndex: 0), isFalse);
    expect(show(selectedIndex: 1), isFalse);
    expect(show(selectedIndex: 2), isFalse);
    expect(show(selectedIndex: 4), isFalse);
    expect(show(selectedIndex: 5), isTrue);
    expect(show(selectedIndex: 5, isPro: true), isFalse);
    expect(show(selectedIndex: 0, easyReadMode: false), isTrue);
  });

  test('speech uses the current language and degrades on web', () async {
    final fake = _FakeSpeech();
    final speaker = ArrivalSpeaker(engine: fake, isWeb: false, isIos: true);
    expect(await speaker.speak('5 分鐘後到', 'zh'), isTrue);
    expect(fake.calls, contains('lang:zh-HK'));
    expect(fake.calls, contains('say:5 分鐘後到'));

    final web = _FakeSpeech()..failLanguages = true;
    final webSpeaker = ArrivalSpeaker(engine: web, isWeb: true, isIos: false);
    expect(await webSpeaker.speak('5 分鐘後到', 'zh'), isFalse);

    expect(await speaker.speak('   ', 'en'), isFalse);
    expect(ArrivalSpeaker.localesFor('zhHans').first, 'zh-CN');
    expect(ArrivalSpeaker.localesFor('pt').first, 'pt-PT');
    expect(ArrivalSpeaker.localesFor('en').first, 'en-US');
  });

  testWidgets('easy read more keeps special routes and the full list', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'language_code': 'zh'});
    final lang = LanguageController();
    await tester.pumpWidget(
      ChangeNotifierProvider<LanguageController>.value(
        value: lang,
        child: const MaterialApp(home: EasyReadMoreScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('特別班次'), findsOneWidget);
    expect(find.text('🚌 全澳巴士路線總覽'), findsOneWidget);
    expect(find.text('車資表'), findsNothing);
    expect(find.text('车资表'), findsNothing);
    expect(find.text('Tarifas'), findsNothing);
    expect(find.text('Fares'), findsNothing);
    expect(find.text('路線規劃'), findsNothing);
    expect(find.text('改道通告'), findsNothing);
    expect(find.text('時間表'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    lang.dispose();
  });

  test('route catalog lines keep the description on its own field', () {
    final lines = RouteCatalogLine.parse(const ['3|關閘 ↔ 外港碼頭', '  ', '10|']);
    expect(lines, hasLength(2));
    expect(lines.first.code, '3');
    expect(lines.first.description, '關閘 ↔ 外港碼頭');
    expect(lines.last.code, '10');
    expect(lines.last.description, isEmpty);
  });
}
