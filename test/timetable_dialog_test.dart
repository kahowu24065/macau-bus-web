import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:macau_bus_app/controllers/language_controller.dart';
import 'package:macau_bus_app/services/dsat_timetable.dart';
import 'package:macau_bus_app/views/widgets/timetable_dialog.dart';

Future<void> _pumpDialog(
  WidgetTester tester, {
  required String route,
  required int direction,
  String language = 'zh',
}) async {
  SharedPreferences.setMockInitialValues({'language_code': language});
  final lang = LanguageController();
  await lang.changeLanguage(language);
  await tester.pumpWidget(
    ChangeNotifierProvider<LanguageController>.value(
      value: lang,
      child: MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => TimetableDialog.show(context, route: route, direction: direction),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await DsatTimetable.ensureLoaded();
  });

  testWidgets('1A dialog shows the DSAT frequency table', (tester) async {
    await _pumpDialog(tester, route: '1A', direction: 0);

    expect(find.text('1A 時間表'), findsOneWidget);
    expect(find.text('服務時間'), findsOneWidget);
    expect(find.text('班次 (分鐘)'), findsOneWidget);
    expect(find.text('星期一至六（公眾假期除外）'), findsOneWidget);
    expect(find.text('星期日及公眾假期'), findsOneWidget);
    expect(find.text('06:00-07:00'), findsOneWidget);
    expect(find.text('9 - 11'), findsOneWidget);
    expect(find.text('班次來自交通事務局（DSAT）官方路線資料'), findsOneWidget);
    expect(find.text('關閉'), findsOneWidget);

    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect(dialog.backgroundColor, const Color(0xFF1E1E1E));
    expect(find.byIcon(Icons.schedule), findsOneWidget);

    await tester.tap(find.text('關閉'));
    await tester.pumpAndSettle();
    expect(find.text('1A 時間表'), findsNothing);
  });

  testWidgets('a route without bands fails with the empty state', (tester) async {
    await _pumpDialog(tester, route: '99Z', direction: 0);

    expect(find.text('99Z 時間表'), findsOneWidget);
    expect(find.text('暫無詳細時間表資料'), findsOneWidget);
    expect(find.text('服務時間'), findsNothing);
    expect(find.textContaining('DSAT'), findsNothing);
    expect(find.text('關閉'), findsOneWidget);
  });

  testWidgets('English uses translated section headers and the DSAT note', (tester) async {
    await _pumpDialog(tester, route: '1A', direction: 1, language: 'en');

    expect(find.text('1A Timetable'), findsOneWidget);
    expect(find.text('Mon–Sat (except public holidays)'), findsOneWidget);
    expect(find.text('Sun & public holidays'), findsOneWidget);
    expect(find.text('Frequencies from official DSAT route information'), findsOneWidget);
    expect(find.text('9 - 11'), findsOneWidget);
  });
}
