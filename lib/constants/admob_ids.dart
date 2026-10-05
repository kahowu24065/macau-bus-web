import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kReleaseMode, TargetPlatform;

/// AdMob application + banner unit IDs.
///
/// Pass `--dart-define=USE_TEST_ADS=true` on a release build (e.g. Codemagic
/// TestFlight preview) to force Google's official sample IDs so banners fill
/// with labeled test creatives. Default is production IDs in release and
/// sample IDs in debug (unchanged).
///
/// Restore production TestFlight: rebuild without `USE_TEST_ADS`, and remove
/// any Info.plist GADApplicationIdentifier override in `codemagic.yaml`.
class AdMobIds {
  AdMobIds._();

  /// Compile-time flag from `--dart-define=USE_TEST_ADS=true`.
  static const bool useTestAds =
      bool.fromEnvironment('USE_TEST_ADS', defaultValue: false);

  // Google sample (https://developers.google.com/admob/ios/test-ads).
  static const String googleSampleIosAppId =
      'ca-app-pub-3940256099942544~1458002511';
  static const String googleSampleAndroidAppId =
      'ca-app-pub-3940256099942544~3347511713';
  static const String googleSampleIosBanner =
      'ca-app-pub-3940256099942544/2934735716';
  static const String googleSampleAndroidBanner =
      'ca-app-pub-3940256099942544/6300978111';

  // Production (MBKa).
  static const String productionIosAppId =
      'ca-app-pub-7648913543953622~4515075984';
  static const String productionAndroidAppId =
      'ca-app-pub-7648913543953622~9721521812';
  static const String productionIosBanner =
      'ca-app-pub-7648913543953622/3201994319';
  static const String productionAndroidBanner =
      'ca-app-pub-7648913543953622/2476533170';

  static bool get _preferSample => useTestAds || !kReleaseMode;

  static String get bannerAdUnitId {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return _preferSample ? googleSampleAndroidBanner : productionAndroidBanner;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return _preferSample ? googleSampleIosBanner : productionIosBanner;
    }
    return '';
  }
}
