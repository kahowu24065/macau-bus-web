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

  /// Arrival read-aloud. On when the controller is missing, matching the default.
  static bool speakArrivals(BuildContext context, {bool listen = true}) {
    try {
      return Provider.of<EasyReadModeController>(context, listen: listen).speakArrivals;
    } on ProviderNotFoundException {
      return true;
    }
  }
}
