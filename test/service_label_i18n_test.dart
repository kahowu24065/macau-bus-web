import 'package:flutter_test/flutter_test.dart';
import 'package:macau_bus_app/utils/service_label_i18n.dart';

void main() {
  const samples = [
    '星期日及公眾假期', '星期一至六（公眾假期除外）', '星期一至五（公眾假期除外）', '每日',
    '星期六、日及公眾假期', '星期六（公眾假期除外）', '星期一至六（強制性假日除外）',
    '星期日及強制性假日', '2026年10月1-7日', '2026年9月12日、19日、25日2026年10月1日及4日',
    '其餘日子', '星期一至五（強制性假日除外）', '星期六、日及強制性假日', '星期一至五',
    '星期一至五（公眾假期及澳門大學休假日除外）', '星期六、日、公眾假期及澳門大學休假日',
    '2026年10月1-4日', '2026年9月25-27日', '不設服務', '06:00-01:15', '奇怪的標題',
  ];
  test('print translations', () {
    for (final s in samples) {
      // ignore: avoid_print
      print('$s | ${ServiceLabelI18n.translate(s, 'en')} | ${ServiceLabelI18n.translate(s, 'pt')} | ${ServiceLabelI18n.translate(s, 'zhHans')}');
    }
    expect(ServiceLabelI18n.translate('星期一至五（公眾假期除外）', 'en'), 'Mon–Fri (except public holidays)');
    expect(ServiceLabelI18n.translate('2026年10月1-7日', 'en'), '1–7 Oct 2026');
    expect(ServiceLabelI18n.translate('奇怪的標題', 'en'), '奇怪的標題');
    expect(ServiceLabelI18n.translate('星期日及公眾假期', 'zh'), '星期日及公眾假期');
  });
}
