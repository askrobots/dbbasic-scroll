// Object version history, against the REAL object server code (local
// sandbox). Creates an object (v1), edits its source (v2), then checks
// Scroll's Objects → Versions tab lists both with the newest as CURRENT, and
// that a package-installed object (no saved edits) shows its installed
// source as the current version instead of an empty tab.
//
//   SOURCE_WRITES=1 tool/desk_sandbox.sh start
//   tool/ui_test.sh versions
//
// Source writes are off on the desk; this only runs on the local sandbox.

import 'dart:convert';
import 'dart:io';

import 'package:dbbasic_scroll/main.dart';
import 'package:dbbasic_scroll/server_profiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/harness.dart';

const _url = String.fromEnvironment(
  'SANDBOX_URL',
  defaultValue: 'http://127.0.0.1:18101/',
);
const _adminToken = String.fromEnvironment('SANDBOX_ADMIN_TOKEN');

Future<Map<String, dynamic>> admin(
  String method,
  String path, [
  Object? body,
]) async {
  final client = HttpClient();
  try {
    final req = await client.openUrl(method, Uri.parse('$_url$path'));
    req.headers.set('Authorization', 'Bearer $_adminToken');
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    return {
      'status': res.statusCode,
      'body': text.isEmpty ? null : jsonDecode(text),
    };
  } finally {
    client.close();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUp(resetAppState);
  tearDown(resetAppState);

  testWidgets('created object shows v1 + v2 (newest current); an installed '
      'object shows its installed source', (tester) async {
    if (_adminToken.isEmpty) return markTestSkipped('sandbox not configured');
    final id = 'demo_versions_${DateTime.now().millisecondsSinceEpoch}';
    final created = await admin('POST', 'admin/objects', {
      'object_id': id,
      'code': 'def GET(request):\n    return {"hello": "v1"}\n',
      'message': 'first version',
      'author': 'dan',
    });
    if (created['status'] == 403) {
      return markTestSkipped(
        'source writes off: SOURCE_WRITES=1 tool/desk_sandbox.sh start',
      );
    }
    // The server has no object-delete route; the sandbox is throwaway (wiped
    // on every start) and the id is unique per run.
    expect(created['status'], anyOf(200, 201), reason: '${created['body']}');
    final edited = await admin('PUT', 'admin/objects/$id?source=true', {
      'code': 'def GET(request):\n    return {"hello": "v2"}\n',
      'message': 'say v2',
      'author': 'dan',
    });
    expect(edited['status'], 200, reason: '${edited['body']}');

    useLaptopSurface(tester);
    await ServerProfileStore().upsert(
      ServerProfile(
        id: ServerProfile.idForUrl(_url),
        name: 'Sandbox admin',
        objectServerUrl: _url,
        token: _adminToken,
      ),
    );
    await tester.pumpWidget(const ScrollApp());
    await pumpUntilFound(tester, find.text('Sandbox admin'));
    await tester.tap(find.text('Sandbox admin'));
    await pumpUntilFound(tester, find.text('APPS'));
    await tester.tap(find.text('Admin'));
    await pumpFor(tester, const Duration(seconds: 1));
    await tapNavItem(tester, 'Objects');
    await pumpUntilFound(tester, find.text('action_nav_entries'));

    await pumpUntilFound(tester, find.text(id));
    // Earlier runs leave objects behind (no object delete), so search.
    await tester.enterText(find.byKey(const Key('object-search')), id);
    await pumpFor(tester, const Duration(milliseconds: 500));
    await tester.tap(find.text(id).last);
    await pumpUntilFound(tester, find.text('Versions'));
    await tester.tap(find.text('Versions'));
    await pumpUntilFound(tester, find.text('say v2'));
    expect(find.text('v2'), findsOneWidget);
    expect(find.text('v1'), findsOneWidget);
    expect(find.text('first version'), findsOneWidget);
    expect(find.text('CURRENT'), findsOneWidget, reason: 'only the newest');
    final current = find.ancestor(
      of: find.text('CURRENT'),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(of: current.first, matching: find.text('v2')),
      findsOneWidget,
      reason: 'v2 is the live one',
    );

    // A package object: never edited, so no saved history on the server.
    await tester.tap(find.byKey(const Key('object-search')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('object-search')),
      'action_nav',
    );
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.text('site_home'), findsNothing, reason: 'search filters');
    await tester.tap(find.text('action_nav_entries').last);
    await pumpFor(tester, const Duration(milliseconds: 500));
    await tester.tap(find.text('Versions')); // selecting resets to Overview
    await pumpUntilFound(tester, find.text('installed'));
    expect(find.text('No version data'), findsNothing);
    expect(find.text('CURRENT'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
