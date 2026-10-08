import 'package:flutter_test/flutter_test.dart';
import 'package:macau_bus_app/utils/alighting_location.dart';

void main() {
  Future<AlightingPermissionDecision> decide({
    required List<String> statuses,
    bool upgradePromptUsed = false,
  }) {
    var index = 0;
    var requests = 0;
    return decideAlightingPermission(
      readStatus: () async => statuses[index],
      requestAlways: () async {
        requests += 1;
        index += 1;
        return statuses[index];
      },
      upgradePromptUsed: upgradePromptUsed,
    ).then((decision) {
      expect(requests, index);
      return decision;
    });
  }

  test('a first request uses the system Always prompt', () async {
    final decision = await decide(statuses: ['notDetermined', 'always']);
    expect(decision.action, AlightingPermissionAction.ready);
    expect(decision.upgradePromptUsed, isFalse);
  });

  test('While Using is upgraded with the system prompt when iOS can still show it', () async {
    final decision = await decide(statuses: ['whenInUse', 'always']);
    expect(decision.action, AlightingPermissionAction.ready);
    expect(decision.upgradePromptUsed, isTrue);
  });

  test('keeping While Using explains that Always is required', () async {
    final decision = await decide(statuses: ['whenInUse', 'whenInUse']);
    expect(decision.action, AlightingPermissionAction.foregroundAndSettings);
    expect(decision.upgradePromptUsed, isTrue);
  });

  test('a weaker choice that iOS will not ask again goes to settings', () async {
    var requests = 0;
    final decision = await decideAlightingPermission(
      readStatus: () async => 'whenInUse',
      requestAlways: () async {
        requests += 1;
        return 'always';
      },
      upgradePromptUsed: true,
    );
    expect(requests, 0);
    expect(decision.action, AlightingPermissionAction.foregroundAndSettings);
  });

  test('a refusal that will not prompt again opens settings instead of the reminder', () async {
    var requests = 0;
    final decision = await decideAlightingPermission(
      readStatus: () async => 'denied',
      requestAlways: () async {
        requests += 1;
        return 'always';
      },
      upgradePromptUsed: false,
    );
    expect(requests, 0);
    expect(decision.action, AlightingPermissionAction.settingsOnly);
  });

  test('declining the first system prompt does not jump to settings', () async {
    final decision = await decide(statuses: ['notDetermined', 'denied']);
    expect(decision.action, AlightingPermissionAction.denied);
  });
}
