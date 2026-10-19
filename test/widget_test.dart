import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wifi_explorer/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows Arabic Wi-Fi Explorer title', (WidgetTester tester) async {
    await tester.pumpWidget(const WifiExplorerApp());
    await tester.pump();
    expect(find.text('كاشف الشبكات الذكي'), findsOneWidget);
    expect(find.text('فحص الشبكات'), findsOneWidget);
  });
}
