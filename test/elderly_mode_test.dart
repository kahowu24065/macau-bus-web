import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:macau_bus_app/constants/app_translations.dart';
import 'package:macau_bus_app/controllers/elderly_mode_controller.dart';
import 'package:macau_bus_app/services/arrival_speaker.dart';
import 'package:macau_bus_app/theme/elderly_theme.dart';
import 'package:macau_bus_app/utils/elderly_arrival.dart';
import 'package:macau_bus_app/views/screens/elderly_more_screen.dart';
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

  test('elderly mode defaults off and persists', () async {
    final first = ElderlyModeController();
    await first.ready;
    expect(first.enabled, isFalse);

    await first.setEnabled(true);
    final second = ElderlyModeController();
    await second.ready;
    expect(second.enabled, isTrue);
  });

  test('fixed controller does not read preferences', () async {
    SharedPreferences.setMockInitialValues({'elderly_mode': true});
    final fixed = ElderlyModeController.fixed(false);
    await fixed.ready;
    expect(fixed.enabled, isFalse);
  });

  test('translations include elderly mode in all four languages', () {
    const keys = [
      'elderly_mode',
      'elderly_mode_desc',
      'elderly_eta_mins',
      'elderly_arriving_next',
      'elderly_arriving_soon',
      'more_options',
      'elderly_stop_closed',
      'elderly_diversion',
      'elderly_no_diversion',
      'elderly_pick_route',
      'elderly_list_empty',
    ];
    for (final lang in ['zh', 'zhHans', 'pt', 'en']) {
      for (final key in keys) {
        expect(AppTranslations.data[lang]![key], isNotNull, reason: '$lang.$key');
        expect(AppTranslations.data[lang]![key]!.trim(), isNotEmpty);
      }
    }
    expect(AppTranslations.data['zh']!['elderly_mode'], '長者模式');
    expect(AppTranslations.data['zh']!['more_options'], '更多');
    expect(AppTranslations.data['zh']!['elderly_eta_mins'], '@mins 分鐘後到');
    expect(AppTranslations.data['zh']!['elderly_mode_desc'], contains('\n'));
    expect(AppTranslations.data['en']!['elderly_mode'], 'Elderly mode');
    expect(AppTranslations.data['pt']!['more_options'], 'Mais');
    expect(AppTranslations.data['zhHans']!['elderly_mode'], '长者模式');
  });

  test('arrival wording keeps next-stop and arriving-soon logic', () {
    String zh(String key) => _tr('zh', key);

    expect(
      approachingStatus(elderly: false, stopsAway: 2, estimatedMins: 4, tr: zh),
      '尚有 2 站 (約 4 分鐘)',
    );
    expect(
      approachingStatus(elderly: false, stopsAway: 1, estimatedMins: 5, tr: zh),
      '下站到達 (約 5 分鐘)',
    );
    expect(
      approachingStatus(elderly: false, stopsAway: 1, estimatedMins: 0, tr: zh),
      '下站到達',
    );
    expect(
      approachingStatus(elderly: false, stopsAway: 0, estimatedMins: 0, tr: zh),
      '即將到站 / 到站中',
    );

    expect(
      approachingStatus(elderly: true, stopsAway: 2, estimatedMins: 4, tr: zh),
      '4 分鐘後到',
    );
    expect(
      approachingStatus(elderly: true, stopsAway: 1, estimatedMins: 5, tr: zh),
      '5 分鐘後到',
    );
    expect(
      approachingStatus(elderly: true, stopsAway: 1, estimatedMins: 0, tr: zh),
      '下一站到達',
    );
    expect(
      approachingStatus(elderly: true, stopsAway: 0, estimatedMins: 0, tr: zh),
      '即將到站',
    );
    expect(
      presentArrivalStatus(elderly: true, status: zh('service_ended'), tr: zh),
      '本日服務已結束',
    );
    expect(
      approachingStatus(
        elderly: true,
        stopsAway: 3,
        estimatedMins: 8,
        tr: (key) => _tr('en', key),
      ),
      'In 8 min',
    );
    expect(
      approachingStatus(
        elderly: true,
        stopsAway: 0,
        estimatedMins: 0,
        tr: (key) => _tr('pt', key),
      ),
      'A chegar',
    );
  });

  test('text scale undo restores the size under the header', () {
    expect(ElderlyTheme.undoTextScale(const TextScaler.linear(1.35)).scale(1), closeTo(1, 0.001));
    expect(
      ElderlyTheme.undoTextScale(const TextScaler.linear(1.2 * 1.35)).scale(1),
      closeTo(1.2, 0.001),
    );
  });

  test('contrast lifts grey and keeps saturated colours in both themes', () {
    expect(ElderlyTheme.lift(Colors.grey.shade500, Brightness.light), ElderlyTheme.lightForeground);
    expect(ElderlyTheme.lift(Colors.grey.shade500, Brightness.dark), Colors.white);
    expect(ElderlyTheme.lift(Colors.white70, Brightness.dark), Colors.white);
    expect(ElderlyTheme.lift(Colors.black54, Brightness.light), ElderlyTheme.lightForeground);
    expect(ElderlyTheme.lift(Colors.amber, Brightness.light), Colors.amber);
    expect(ElderlyTheme.lift(Colors.black, Brightness.light), Colors.black);
    expect(ElderlyTheme.lift(Colors.white, Brightness.dark), Colors.white);

    final light = ElderlyTheme.apply(ThemeData.light());
    final dark = ElderlyTheme.apply(ThemeData.dark());
    expect(light.textButtonTheme.style?.minimumSize?.resolve({}), const Size(72, 56));
    expect(dark.colorScheme.onSurface, Colors.white);
    expect(light.colorScheme.onSurface, ElderlyTheme.lightForeground);
    expect(light.textTheme.bodyMedium?.fontWeight, FontWeight.w700);
    expect(dark.textTheme.bodyMedium?.fontWeight, FontWeight.w700);
  });

  test('elderly mode hides every ad slot except settings', () {
    bool show({required int selectedIndex, bool elderlyMode = true, bool isPro = false}) {
      return showHomeBannerSlot(
        isWeb: false,
        isPro: isPro,
        showMapView: false,
        selectedIndex: selectedIndex,
        isPlanningRoute: false,
        elderlyMode: elderlyMode,
      );
    }

    expect(show(selectedIndex: 0), isFalse);
    expect(show(selectedIndex: 1), isFalse);
    expect(show(selectedIndex: 2), isFalse);
    expect(show(selectedIndex: 4), isFalse);
    expect(show(selectedIndex: 5), isTrue);
    expect(show(selectedIndex: 5, isPro: true), isFalse);
    expect(show(selectedIndex: 0, elderlyMode: false), isTrue);
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

  test('route catalog lines keep the description on its own field', () {
    final lines = RouteCatalogLine.parse(const ['3|關閘 ↔ 外港碼頭', '  ', '10|']);
    expect(lines, hasLength(2));
    expect(lines.first.code, '3');
    expect(lines.first.description, '關閘 ↔ 外港碼頭');
    expect(lines.last.code, '10');
    expect(lines.last.description, isEmpty);
  });
}
