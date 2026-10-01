export 'http_overrides_setup_stub.dart'
    if (dart.library.io) 'http_overrides_setup_io.dart'
    if (dart.library.html) 'http_overrides_setup_web.dart';
