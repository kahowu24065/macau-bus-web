import 'dart:io';

class _TimeoutHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..connectionTimeout = const Duration(seconds: 5)
      ..idleTimeout = const Duration(seconds: 8);
  }
}

void installApiHttpOverrides() {
  HttpOverrides.global = _TimeoutHttpOverrides();
}
