import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_explorer/main.dart';

void main() {
  testWidgets('shows Arabic Wi-Fi Explorer title', (WidgetTester tester) async {
    await tester.pumpWidget(const WifiExplorerApp());
    expect(find.text('كاشف الشبكات الذكي'), findsOneWidget);
    expect(find.text('فحص الشبكات'), findsOneWidget);
  });
}
