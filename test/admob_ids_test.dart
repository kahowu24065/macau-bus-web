import 'package:flutter_test/flutter_test.dart';
import 'package:macau_bus_app/constants/admob_ids.dart';

void main() {
  test('USE_TEST_ADS defaults to false (production path available)', () {
    expect(AdMobIds.useTestAds, isFalse);
    expect(AdMobIds.productionIosBanner, contains('7648913543953622'));
    expect(AdMobIds.googleSampleIosBanner, contains('3940256099942544'));
  });
}
