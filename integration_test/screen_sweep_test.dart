// Smoke sweep: open every admin screen and report any that throw (build
// errors, layout overflows, bad casts on unexpected response shapes).
// This finds crashes, NOT logic bugs: the fake server returns minimal bodies.
//
// Run:  tool/ui_test.sh integration_test/screen_sweep_test.dart

import 'package:dbbasic_scroll/main.dart';
import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/fake_object_server.dart';
import 'support/harness.dart';

const _screens = [
  'Search',
  'Chat',
  'Collections',
  'Objects',
  'Stations',
  'Users',
  'Permissions',
  'API',
  'SQL',
  'Query',
  'Daemon',
  'Changes',
  'Ops',
  'Files',
  'Schema',
  'Diagram',
  'Packages',
  'Backup',
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<Map<String, String>> sweep(
    WidgetTester tester,
    FakeObjectServer server, {
    Size size = const Size(1440, 900),
  }) async {
    useLaptopSurface(tester, size: size);
    await tester.pumpWidget(const ScrollApp());
    await pumpUntilFound(tester, find.text('Connect to your object server'));
    await tester.enterText(
      textFieldLabelled('Object Server URL (required)'),
      server.url,
    );
    await tester.enterText(textFieldLabelled('Bearer Token'), 'dbk_sweep-key');
    await tester.tap(find.text('Connect'));
    await pumpUntilFound(tester, find.text('What would you like to do?'));
    await pumpFor(tester, const Duration(seconds: 2));
    final failures = <String, String>{};
    // Home (and the app bar) count too: a narrow-window app-bar overflow
    // was once hidden by discarding this exception.
    final homeError = tester.takeException();
    if (homeError != null) {
      failures['Home'] = homeError.toString().split('\n').first;
    }

    await tester.tap(find.text('Admin'));
    await pumpFor(tester, const Duration(milliseconds: 500));

    for (final label in _screens) {
      try {
        await tapNavItem(tester, label);
      } catch (_) {
        failures[label] = 'nav item not found';
        continue;
      }
      await pumpFor(tester, const Duration(milliseconds: 1500));
      final error = tester.takeException();
      if (error != null) {
        failures[label] = error.toString().split('\n').first;
        // ignore: avoid_print
        print('SWEEP   DETAIL $label:\n$error');
      }
    }
    return failures;
  }

  void report(String title, Map<String, String> failures) {
    // ignore: avoid_print
    print(
      'SWEEP $title: ${_screens.length - failures.length}/${_screens.length} '
      'screens opened cleanly',
    );
    failures.forEach(
      (k, v) => print('SWEEP   FAIL $k: $v'),
    ); // ignore: avoid_print
  }

  testWidgets('every admin screen opens in a small 720x600 window', (
    tester,
  ) async {
    await resetAppState();
    final server = FakeObjectServer(adminGated: false)..aiUsageRows = [];
    await server.start();
    addTearDown(() async {
      await resetAppState();
      await server.stop();
    });
    final failures = await sweep(tester, server, size: const Size(720, 600));
    report('720x600', failures);
    expect(failures, isEmpty);
  });

  for (final locked in [true, false]) {
    testWidgets(
      locked
          ? 'every admin screen opens when admin routes answer 401 (locked)'
          : 'every admin screen opens when admin routes answer 200 {status: ok}',
      (tester) async {
        await resetAppState();
        final server = FakeObjectServer(adminGated: locked)..aiUsageRows = [];
        await server.start();
        addTearDown(() async {
          await resetAppState();
          await server.stop();
        });

        final failures = await sweep(tester, server);
        report(locked ? 'locked' : 'allowed', failures);
        expect(failures, isEmpty);
      },
    );
  }
}
