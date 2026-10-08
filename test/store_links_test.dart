import 'package:flutter_test/flutter_test.dart';
import 'package:macau_bus_app/constants/store_links.dart';

void main() {
  test('listing URLs point at the live Akar pages', () {
    expect(StoreLinks.marketing, 'https://akar-apps.pages.dev/');
    expect(StoreLinks.support, 'https://akar-apps.pages.dev/mbka/support');
    expect(StoreLinks.privacy, 'https://akar-apps.pages.dev/mbka/privacy');
    for (final url in StoreLinks.all) {
      expect(url.contains('macaubus-kat1.com'), isFalse);
    }
  });
}
