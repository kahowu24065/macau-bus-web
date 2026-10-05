/// App Store Connect and Play Console listing URLs.
///
/// The pages are already live. The bus API stays on macaubus-kat1.com, and
/// that host's app-ads.txt stays until the store listing URLs are changed.
abstract final class StoreLinks {
  static const String marketing = 'https://akar-apps.pages.dev/';
  static const String support = 'https://akar-apps.pages.dev/support';
  static const String privacy = 'https://akar-apps.pages.dev/privacy';

  static const List<String> all = [marketing, support, privacy];
}
