import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbbasic_scroll/main.dart';

void main() {
  testWidgets('shows connect screen when no saved connection', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const ScrollApp());
    await tester.pumpAndSettle();

    expect(find.text('DBBasic Scroll'), findsOneWidget);
    expect(find.text('Connect to your object server'), findsOneWidget);
  });
}
