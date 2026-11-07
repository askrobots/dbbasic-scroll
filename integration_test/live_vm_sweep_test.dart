// LIVE, read-only GUI sweep against a real object server (the nc desk via the
// SSH tunnel by default). Opt-in only:
//
//   tool/ui_test.sh integration_test/live_vm_sweep_test.dart \
//       --dart-define=SCROLL_LIVE=true [--dart-define=SCROLL_LIVE_URL=http://127.0.0.1:18001/]
//
// * Uses the credential already saved in Scroll (a saved connection for that
//   URL). The token is never printed.
// * Opens only screens whose on-open requests are GETs. Excluded on privacy
//   grounds: Chat (replays shell_commands AI turns), Users (lists identity
//   sessions), Files (lists the user's files).
// * Writes a PNG per screen to the app's sandbox tmp dir and prints only the
//   app's own status/error strings, never record contents.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:dbbasic_scroll/api.dart';
import 'package:dbbasic_scroll/main.dart';
import 'package:dbbasic_scroll/server_profiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/harness.dart';

const _live = bool.fromEnvironment('SCROLL_LIVE');
const _url = String.fromEnvironment(
  'SCROLL_LIVE_URL',
  defaultValue: 'http://127.0.0.1:18001/',
);

const _adminScreens = [
  'Search',
  'Collections',
  'Objects',
  'Stations',
  'Permissions',
  'API',
  'SQL',
  'Query',
  'Daemon',
  'Changes',
  'Ops',
  'Schema',
  'Diagram',
  'Packages',
  'Backup',
];

final _statusPattern = RegExp(
  r'(Locked|Failed|failed|HTTP \d|error|Error|Not enabled|unavailable|'
  r'Unauthorized|not found|No |Could not|denied|locked)',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final shotKey = GlobalKey();
  final outDir = Directory('${Directory.systemTemp.path}/scroll_live');

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.runAsync(() async {
      final boundary =
          shotKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await outDir.create(recursive: true);
      await File(
        '${outDir.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  /// The app's own status/error strings currently on screen (not data).
  List<String> statusLines() {
    final out = <String>{};
    for (final e in find.byType(Text).evaluate()) {
      final t = (e.widget as Text).data;
      if (t != null && t.length < 300 && _statusPattern.hasMatch(t)) {
        out.add(t.replaceAll('\n', ' '));
      }
    }
    return out.toList();
  }

  testWidgets('LIVE read-only sweep of $_url', (tester) async {
    if (!_live) {
      markTestSkipped('set --dart-define=SCROLL_LIVE=true to run');
      return;
    }
    final profiles = await ServerProfileStore().list();
    final profile = profiles
        .where((p) => p.objectServerUrl == _url)
        .firstOrNull;
    expect(
      profile,
      isNotNull,
      reason:
          'No saved Scroll connection for $_url. Saved: '
          '${profiles.map((p) => p.objectServerUrl).toList()}',
    );
    // ignore: avoid_print
    print('LIVE profile "${profile!.name}" -> ${profile.objectServerUrl}');
    // ignore: avoid_print
    print('LIVE screenshots -> ${outDir.path}');

    // Relaunch path first: the saved connection as the app restores it.
    await ScrollAPI().loadSavedConnection();
    // ignore: avoid_print
    print('LIVE relaunch credential kind: ${ScrollAPI().credentialKind.name}');
    if (profile.token.startsWith('dbk_')) {
      expect(ScrollAPI().credentialKind, CredentialKind.apiKey);
    }

    final error = await activateProfile(profile);
    expect(error, isNull, reason: error);

    useLaptopSurface(tester);
    await tester.pumpWidget(
      RepaintBoundary(key: shotKey, child: const ScrollApp()),
    );
    await pumpUntilFound(tester, find.text('What would you like to do?'));
    await pumpFor(tester, const Duration(seconds: 4));
    final report = <String, List<String>>{};
    void record(String screen) {
      final ex = tester.takeException();
      report[screen] = [
        if (ex != null) 'EXCEPTION: ${ex.toString().split('\n').first}',
        ...statusLines(),
      ];
    }

    record('Home');
    await shot(tester, '00_home');

    // AI Usage (numbers and model names only).
    await tester.ensureVisible(find.text('AI Usage'));
    await tester.tap(find.text('AI Usage'));
    await pumpUntilFound(tester, find.text('READ ONLY'));
    await pumpFor(tester, const Duration(seconds: 3));
    record('AI Usage');
    await shot(tester, '01_ai_usage');

    await tester.tap(find.text('Admin'));
    await pumpFor(tester, const Duration(seconds: 1));
    var i = 2;
    for (final label in _adminScreens) {
      try {
        await tapNavItem(tester, label);
      } catch (_) {
        report[label] = ['nav item not found'];
        continue;
      }
      await pumpFor(tester, const Duration(seconds: 3));
      record(label);
      await shot(
        tester,
        '${(i++).toString().padLeft(2, '0')}_${label.toLowerCase()}',
      );
    }

    // ignore: avoid_print
    print(
      'LIVE admin status available: ${ScrollAPI().authRejected.value ? 'AUTH REJECTED' : 'ok'}',
    );
    report.forEach((screen, lines) {
      // ignore: avoid_print
      print(
        'LIVE [$screen] ${lines.isEmpty ? '(no status messages)' : lines.join(' | ')}',
      );
    });
    expect(
      report.values.expand((l) => l).where((l) => l.startsWith('EXCEPTION')),
      isEmpty,
    );
    expect(
      find.text('Session expired'),
      findsNothing,
      reason: 'a valid credential must never be told to sign in again',
    );
    expect(ScrollAPI().authRejected.value, isFalse);
  });
}
