import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../controllers/easy_read_mode_controller.dart';

/// Reads easy read mode without forcing every screen test to provide it.
/// Missing controller means off, which is the default.
class EasyReadAccess {
  static bool enabled(BuildContext context, {bool listen = true}) {
    try {
      return Provider.of<EasyReadModeController>(context, listen: listen).enabled;
    } on ProviderNotFoundException {
      return false;
    }
  }

  /// Arrival read-aloud for the active mode.
  /// A missing controller follows the normal-mode default, which is off.
  static bool speakArrivals(BuildContext context, {bool listen = true}) {
    try {
      return Provider.of<EasyReadModeController>(context, listen: listen).speakArrivals;
    } on ProviderNotFoundException {
      return false;
    }
  }

  /// Read-aloud language. A missing controller follows [appLanguage].
  static String speechLanguage(BuildContext context, String appLanguage, {bool listen = true}) {
    try {
      return Provider.of<EasyReadModeController>(context, listen: listen).speechLanguageFor(appLanguage);
    } on ProviderNotFoundException {
      return EasyReadModeController.defaultSpeechLanguage(appLanguage);
    }
  }
}
