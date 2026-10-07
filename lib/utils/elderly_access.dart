import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../controllers/elderly_mode_controller.dart';

/// Reads elderly mode without forcing every screen test to provide it.
/// Missing controller means off, which is the default.
class ElderlyAccess {
  static bool enabled(BuildContext context, {bool listen = true}) {
    try {
      return Provider.of<ElderlyModeController>(context, listen: listen).enabled;
    } on ProviderNotFoundException {
      return false;
    }
  }
}
