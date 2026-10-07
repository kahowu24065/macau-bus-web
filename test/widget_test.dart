import 'package:flutter_test/flutter_test.dart';
import 'package:macau_bus_app/constants/app_translations.dart';

void main() {
  test('the app keeps its traditional Chinese name', () {
    expect(AppTranslations.data['zh']!['settings_title'], contains('設定'));
    expect(AppTranslations.data['zh']!['elderly_mode'], '長者模式');
  });
}
