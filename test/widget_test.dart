import 'package:flutter_test/flutter_test.dart';
import 'package:robo_commander/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const RoboCommanderApp());
    expect(find.byType(RoboCommanderApp), findsOneWidget);
  });
}
