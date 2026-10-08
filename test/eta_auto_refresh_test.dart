import 'package:flutter_test/flutter_test.dart';
import 'package:macau_bus_app/controllers/bus_controller.dart';
import 'package:macau_bus_app/models/bus.dart';
import 'package:macau_bus_app/services/bus_api_service.dart';
import 'package:macau_bus_app/services/open_data_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OpenDataConfig.instance.debugApply(configRealtime: true, etaRealtime: true);
  });

  tearDown(() {
    BusApiService.debugFetchBusETA = null;
    OpenDataConfig.instance.debugReset();
  });

  Map<String, dynamic> etaBody() => {
        'success': true,
        'etaData': {'status': '約 2 分鐘'},
        'allBuses': <Bus>[],
      };

  testWidgets('automatic ETA refresh asks about every 10 seconds', (tester) async {
    final calls = <int?>[];
    BusApiService.debugFetchBusETA = (
      String route,
      int dir, {
      int? targetStopSeq,
      String lang = 'zh',
    }) async {
      calls.add(targetStopSeq);
      return etaBody();
    };

    final bus = BusController();
    try {
      bus.currentRoute = '22';
      bus.selectStop(4);
      bus.startAutoRefresh();

      expect(bus.countdownSeconds, BusController.etaAutoRefreshSeconds);
      expect(calls, isEmpty);

      // Five seconds is still inside the interval, so no poll yet.
      await tester.pump(const Duration(seconds: 5));
      expect(calls, isEmpty);
      expect(bus.countdownSeconds, 5);

      await tester.pump(const Duration(seconds: 4));
      expect(calls, isEmpty);
      expect(bus.countdownSeconds, 1);

      await tester.pump(const Duration(seconds: 1));
      expect(calls, [4]);
      expect(bus.countdownSeconds, BusController.etaAutoRefreshSeconds);

      await tester.pump(const Duration(seconds: 9));
      expect(calls, [4]);

      await tester.pump(const Duration(seconds: 1));
      expect(calls, [4, 4]);
    } finally {
      bus.dispose();
    }
  });

  testWidgets('a manual ETA refresh still fetches immediately', (tester) async {
    final calls = <int?>[];
    BusApiService.debugFetchBusETA = (
      String route,
      int dir, {
      int? targetStopSeq,
      String lang = 'zh',
    }) async {
      calls.add(targetStopSeq);
      return etaBody();
    };

    final bus = BusController();
    try {
      bus.currentRoute = '22';
      bus.startAutoRefresh();

      await tester.pump(const Duration(seconds: 3));
      expect(calls, isEmpty);

      // Opening a stop, or the refresh button, calls fetchBusETA directly.
      bus.selectStop(7);
      await bus.fetchBusETA();
      expect(calls, [7]);
      expect(bus.countdownSeconds, BusController.etaAutoRefreshSeconds);

      // That immediate fetch restarts the auto-refresh countdown.
      await tester.pump(const Duration(seconds: 9));
      expect(calls, [7]);

      await tester.pump(const Duration(seconds: 1));
      expect(calls, [7, 7]);
    } finally {
      bus.dispose();
    }
  });
}
