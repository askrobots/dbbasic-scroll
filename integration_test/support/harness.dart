import 'package:dbbasic_scroll/api.dart';
import 'package:dbbasic_scroll/data.dart';
import 'package:dbbasic_scroll/realtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reset every process-wide singleton and use in-memory preferences, so a test
/// never reads or writes the developer's real saved connections or tokens.
Future<void> resetAppState() async {
  SharedPreferences.setMockInitialValues({});
  ScrollRealtime().shutdown();
  await ScrollAPI().disconnect();
  ScrollData().clear();
}

/// Pump real time until [finder] matches, or fail with [reason] after
/// [timeout]. (`pumpAndSettle` never settles here: the shell has periodic
/// timers and a reconnecting websocket.)
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail(reason ?? 'Timed out waiting for $finder');
}

/// Pump for a fixed real duration (lets background loads finish).
Future<void> pumpFor(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder textFieldLabelled(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
  description: 'TextField labelled "$label"',
);

/// A fixed laptop-sized surface (1440x900 logical). The macOS test window's
/// size otherwise depends on the machine and the app's saved window frame.
void useLaptopSurface(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Tap an item in the admin nav rail, scrolling the rail until it is built
/// and visible (the rail is a lazy ListView; far items may not exist yet).
Future<void> tapNavItem(WidgetTester tester, String label) async {
  final item = find.descendant(
    of: find.byKey(const Key('admin-nav-rail')),
    matching: find.text(label),
  );
  await tester.scrollUntilVisible(
    item,
    60,
    scrollable: find
        .descendant(
          of: find.byKey(const Key('admin-nav-rail')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pump();
  await tester.tap(item);
}
