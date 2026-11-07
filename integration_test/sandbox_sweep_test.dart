// Every screen, signed in the way the desk will be used once session admin
// gates are on: the real Connect screen, password sign-in as user id "dan",
// against the local sandbox (tool/desk_sandbox.sh with SESSION_ADMIN=1).
//
//   SESSION_ADMIN=1 tool/desk_sandbox.sh start
//   tool/ui_test.sh sweep
//
// Writes a PNG per screen to <app tmp>/scroll_sweep and prints the app's own
// status/error strings per screen. Sandbox data only, in-memory preferences.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:dbbasic_scroll/api.dart';
import 'package:dbbasic_scroll/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/harness.dart';

const _url = String.fromEnvironment(
  'SANDBOX_URL',
  defaultValue: 'http://127.0.0.1:18101/',
);
const _password = String.fromEnvironment('SANDBOX_PASSWORD');

const adminScreens = [
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

final _statusPattern = RegExp(
  r'(Locked|Failed|failed|HTTP \d|error|Error|Not enabled|unavailable|'
  r'Unauthorized|not found|No |Could not|denied|locked|demo|sample|—)',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final shotKey = GlobalKey();
  final outDir = Directory('${Directory.systemTemp.path}/scroll_sweep');

  setUp(resetAppState);
  tearDown(resetAppState);

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

  testWidgets('password sign-in as "dan", then every screen', (tester) async {
    if (_password.isEmpty) return markTestSkipped('sandbox not configured');
    if (await outDir.exists()) await outDir.delete(recursive: true);
    // ignore: avoid_print
    print('SWEEP screenshots -> ${outDir.path}');

    // A typical laptop window (the default test surface is 800x600).
    useLaptopSurface(tester);
    await tester.pumpWidget(
      RepaintBoundary(key: shotKey, child: const ScrollApp()),
    );
    await pumpUntilFound(tester, find.text('Token or API key'));
    await tester.enterText(
      textFieldLabelled('Object Server URL (required)'),
      _url,
    );
    await tester.tap(find.text('Password'));
    await pumpFor(tester, const Duration(milliseconds: 300));
    await tester.enterText(textFieldLabelled('Email or user id'), 'dan');
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Password',
      ),
      _password,
    );
    await tester.ensureVisible(find.text('Sign In'));
    await pumpFor(tester, const Duration(milliseconds: 300));
    await tester.tap(find.text('Sign In'));
    await pumpUntilFound(
      tester,
      find.text('What would you like to do?'),
      timeout: const Duration(seconds: 20),
      reason: 'password sign-in with a user id should reach the dashboard',
    );
    expect(ScrollAPI().credentialKind, CredentialKind.session);
    expect(ScrollAPI().sessionUserId, 'dan');
    await pumpFor(tester, const Duration(seconds: 4));

    final report = <String, List<String>>{};
    void record(String screen) {
      final ex = tester.takeException();
      report[screen] = [
        if (ex != null) 'EXCEPTION: ${ex.toString().split('\n').first}',
        ...statusLines(),
      ];
    }

    // Soft checks: every screen is checked, all failures reported at once.
    final failures = <String>[];
    void want(String screen, Finder f, Matcher m, String what) {
      try {
        expect(f, m);
      } on TestFailure {
        failures.add('[$screen] $what');
      }
    }

    record('Home');
    await shot(tester, '00_home');
    // Home is built from the server's own collections (no platform here).
    want('Home', find.text('Notes'), findsWidgets, 'a Notes view');
    want('Home', find.text('New Note'), findsOneWidget, 'a New Note action');
    // Planned features stay visible, clearly marked as mockups (pink tag),
    // and platform-only ones say why they're unavailable.
    for (final planned in ['Recent Orders', 'Monthly Sales', 'New Invoice']) {
      want(
        'Home',
        find.text(planned),
        findsOneWidget,
        'mockup "$planned" kept',
      );
    }
    want('Home', find.text('MOCKUP'), findsWidgets, 'mockups are tagged');
    // App bar fills the width: the Admin toggle sits at the right edge
    // (a flexible search box once left a gap there).
    final adminRight = tester.getRect(find.text('Admin').first).right;
    if (adminRight < 1440 - 60) {
      failures.add('[Home] app bar leaves a gap: Admin ends at $adminRight');
    }
    await tester.ensureVisible(find.text('Recent Orders'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    await shot(tester, '00b_home_views');
    await tester.ensureVisible(find.text('Monthly Sales'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    await shot(tester, '00c_home_reports');
    await tester.ensureVisible(find.text('New Note'));
    await pumpFor(tester, const Duration(milliseconds: 300));
    want(
      'Home',
      find.text('needs a platform'),
      findsWidgets,
      'platform tiles explain they need a platform',
    );

    // Create a note from Home, through the schema form, as dan.
    final stamp = DateTime.now().millisecondsSinceEpoch;
    await tester.tap(find.text('New Note'));
    await pumpUntilFound(tester, find.byType(AlertDialog));
    final contentField = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            (w.decoration?.labelText ?? '').toLowerCase().contains('content'),
      ),
    );
    await tester.enterText(contentField.first, 'home note $stamp');
    await tester.tap(find.text('Create Record'));
    await pumpUntilFound(tester, find.text('Created in notes'));
    final notes = await ScrollAPI().listUserCollectionRecords('notes');
    final mine = ((notes['body'] as Map)['records'] as List)
        .whereType<Map>()
        .where((r) => r['content'] == 'home note $stamp')
        .toList();
    want('Home', find.text('Created in notes'), findsOneWidget, 'create toast');
    if (mine.length != 1 || mine.first['owner_id'] != 'dan') {
      failures.add('[Home] New Note reached the server owned by dan');
    }
    await pumpFor(tester, const Duration(seconds: 1));

    await tester.ensureVisible(find.text('AI Usage'));
    await tester.tap(find.text('AI Usage'));
    await pumpFor(tester, const Duration(seconds: 3));
    record('AI Usage');
    await shot(tester, '01_ai_usage');

    await tester.tap(find.text('Admin'));
    await pumpFor(tester, const Duration(seconds: 1));
    var i = 2;
    for (final label in adminScreens) {
      try {
        await tapNavItem(tester, label);
      } catch (_) {
        report[label] = ['nav item not found'];
        continue;
      }
      await pumpFor(tester, const Duration(seconds: 3));
      record(label);
      switch (label) {
        case 'Collections':
          want(
            label,
            find.text('OBJECT NAMESPACE'),
            findsNothing,
            'opens on a record collection',
          );
        case 'Schema':
          want(
            label,
            find.text('No fields'),
            findsNothing,
            'opens on a schema with fields',
          );
        case 'Query':
          await tester.tap(find.text('Run'));
          await pumpFor(tester, const Duration(seconds: 2));
          want(
            label,
            find.textContaining('loaded rows match'),
            findsOneWidget,
            'Run loads real records',
          );
          want(
            label,
            find.text('home note $stamp'),
            findsOneWidget,
            'the note created from Home is in the table',
          );
          // Edit it through the schema form (a session can read schemas).
          if (find.text('home note $stamp').evaluate().isNotEmpty) {
            await tester.tap(find.text('home note $stamp'));
            await pumpUntilFound(tester, find.text('Edit'));
            await tester.tap(find.text('Edit'));
            await pumpUntilFound(tester, find.text('Save Record'));
            final field = find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byWidgetPredicate(
                (w) =>
                    w is TextField &&
                    (w.decoration?.labelText ?? '').toLowerCase().contains(
                      'content',
                    ),
              ),
            );
            await tester.enterText(field.first, 'home note $stamp edited');
            await tester.tap(find.text('Save Record'));
            await pumpFor(tester, const Duration(seconds: 3));
            final after = await ScrollAPI().listUserCollectionRecords('notes');
            final rows = ((after['body'] as Map)['records'] as List)
                .whereType<Map>()
                .where((r) => r['content'] == 'home note $stamp edited')
                .toList();
            if (rows.length != 1 || rows.first['owner_id'] != 'dan') {
              failures.add('[Query] schema-form edit reached the server');
            }
            want(
              label,
              find.text('home note $stamp edited'),
              findsOneWidget,
              'table reloads after the edit',
            );
          }
        case 'Diagram':
          want(
            label,
            find.text('project_id → projects'),
            findsWidgets,
            'real relation tasks/notes → projects',
          );
          await tester.tap(find.text('Design mockup'));
          await pumpFor(tester, const Duration(seconds: 1));
          want(
            label,
            find.text('Contacts'),
            findsOneWidget,
            'the design mockup is still there behind its toggle',
          );
          want(label, find.text('MOCKUP'), findsOneWidget, 'and is tagged');
          await tester.tap(find.text('Live schema'));
          await pumpFor(tester, const Duration(seconds: 1));
        case 'SQL':
          want(label, find.text('MOCKUP'), findsOneWidget, 'banner on SQL');
        case 'Permissions':
          want(
            label,
            find.text('not reported'),
            findsNothing,
            'every row filled from the real server',
          );
      }
      await shot(
        tester,
        '${(i++).toString().padLeft(2, '0')}_${label.toLowerCase()}',
      );
    }

    report.forEach((screen, lines) {
      // ignore: avoid_print
      print(
        'SWEEP [$screen] ${lines.isEmpty ? '(no status messages)' : lines.join(' | ')}',
      );
    });
    expect(
      report.values.expand((l) => l).where((l) => l.startsWith('EXCEPTION')),
      isEmpty,
    );
    expect(find.text('Session expired'), findsNothing);
    expect(ScrollAPI().adminLocked.value, isFalse);
    for (final r in mine) {
      await ScrollAPI().deleteAdminCollectionRecord('notes', '${r['id']}');
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });
}
