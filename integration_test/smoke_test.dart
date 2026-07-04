import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:dbbasic_scroll/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App launches and shows either connect or main screen', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Should show either the connect screen OR the main shell (if auto-connected)
    final hasConnect = find.text('Connect to your object server').evaluate().isNotEmpty;
    final hasMainShell = find.text('DBBasic Scroll').evaluate().isNotEmpty;

    expect(hasConnect || hasMainShell, isTrue,
        reason: 'Should show connect screen or main shell');
  });

  testWidgets('If connected, switchboard loads', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // If we auto-connected, the switchboard should be visible
    final hasSwitchboard = find.text('What would you like to do?').evaluate().isNotEmpty;
    if (hasSwitchboard) {
      // Quick actions should exist
      expect(find.text('QUICK ACTIONS'), findsOneWidget);
      expect(find.text('VIEWS'), findsOneWidget);
      expect(find.text('REPORTS'), findsOneWidget);

      // At least one view tile
      expect(find.text('Contacts'), findsOneWidget);
      expect(find.text('Projects'), findsOneWidget);
    }
  });
}
