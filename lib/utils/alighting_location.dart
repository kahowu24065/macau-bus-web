/// What to do after asking iOS for Always location for the alighting reminder.
enum AlightingPermissionAction {
  /// Always is granted. Start the reminder.
  ready,

  /// Only While Using is granted, and iOS will not show the Always prompt again.
  /// The foreground reminder can start, and the app explains how to allow Always.
  foregroundAndSettings,

  /// Location was refused and the system prompt will not appear again.
  settingsOnly,

  /// The system prompt was just shown and the user did not allow location.
  denied,
}

class AlightingPermissionDecision {
  final AlightingPermissionAction action;

  /// True after the one-time "Change to Always Allow" prompt has been requested.
  final bool upgradePromptUsed;

  const AlightingPermissionDecision({
    required this.action,
    required this.upgradePromptUsed,
  });
}

/// Decides how the alighting reminder asks for Always location.
///
/// [readStatus] and [requestAlways] talk to iOS. [requestAlways] is called
/// only when the system can still show a prompt. A weaker choice that iOS
/// will not ask about again is left for the app to explain.
Future<AlightingPermissionDecision> decideAlightingPermission({
  required Future<String> Function() readStatus,
  required Future<String> Function() requestAlways,
  required bool upgradePromptUsed,
}) async {
  var used = upgradePromptUsed;
  var status = await readStatus();
  if (status == 'notDetermined') used = false;

  if (status == 'always') {
    return AlightingPermissionDecision(action: AlightingPermissionAction.ready, upgradePromptUsed: used);
  }

  if (status == 'notDetermined') {
    status = await requestAlways();
    if (status == 'always') {
      return AlightingPermissionDecision(action: AlightingPermissionAction.ready, upgradePromptUsed: used);
    }
    if (status == 'whenInUse' && !used) {
      used = true;
      status = await requestAlways();
      if (status == 'always') {
        return AlightingPermissionDecision(action: AlightingPermissionAction.ready, upgradePromptUsed: used);
      }
      if (status == 'whenInUse') {
        return AlightingPermissionDecision(
          action: AlightingPermissionAction.foregroundAndSettings,
          upgradePromptUsed: used,
        );
      }
    }
    return AlightingPermissionDecision(
      action: AlightingPermissionAction.denied,
      upgradePromptUsed: used,
    );
  }

  if (status == 'whenInUse') {
    if (!used) {
      used = true;
      status = await requestAlways();
      if (status == 'always') {
        return AlightingPermissionDecision(action: AlightingPermissionAction.ready, upgradePromptUsed: used);
      }
    }
    return AlightingPermissionDecision(
      action: AlightingPermissionAction.foregroundAndSettings,
      upgradePromptUsed: used,
    );
  }

  return AlightingPermissionDecision(
    action: AlightingPermissionAction.settingsOnly,
    upgradePromptUsed: used,
  );
}
