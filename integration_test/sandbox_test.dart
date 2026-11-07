// UI tests against the REAL object server code (a local sandbox copy of the
// nc desk, see tool/desk_sandbox.sh), not a fake. Opt-in:
//
//   tool/desk_sandbox.sh start
//   tool/ui_test.sh sandbox
//
// Uses in-memory preferences, so Dan's saved connections are never touched.

import 'dart:convert';
import 'dart:io';

import 'package:dbbasic_scroll/api.dart';
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
const _apiKey = String.fromEnvironment('SANDBOX_API_KEY');
const _adminToken = String.fromEnvironment('SANDBOX_ADMIN_TOKEN');
const _password = String.fromEnvironment('SANDBOX_PASSWORD');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final configured =
      _apiKey.isNotEmpty && _adminToken.isNotEmpty && _password.isNotEmpty;

  setUp(resetAppState);
  tearDown(resetAppState);

  Future<void> connectVia(
    WidgetTester tester,
    String name,
    String token, {
    String? sessionUser,
  }) async {
    await ServerProfileStore().upsert(
      ServerProfile(
        id: ServerProfile.idForUrl(_url),
        name: name,
        objectServerUrl: _url,
        token: token,
        sessionUserId: sessionUser,
      ),
    );
    useLaptopSurface(tester);
    await tester.pumpWidget(const ScrollApp());
    await pumpUntilFound(tester, find.text(name));
    await tester.tap(find.text(name));
    await pumpUntilFound(tester, find.text('What would you like to do?'));
    await pumpFor(tester, const Duration(seconds: 3));
  }

  Future<void> openAdmin(WidgetTester tester, String screen) async {
    if (find.text('Admin Mode').evaluate().isEmpty &&
        find.text('Admin Mode (locked)').evaluate().isEmpty) {
      await tester.tap(find.text('Admin'));
      await pumpFor(tester, const Duration(milliseconds: 500));
    }
    await tapNavItem(tester, screen);
    await pumpFor(tester, const Duration(seconds: 2));
  }

  /// A real password session with a short TTL, created on the sandbox.
  Future<String> loginSession(int ttlSeconds) async {
    final client = HttpClient();
    try {
      final req = await client.postUrl(Uri.parse('${_url}identity/session'));
      req.headers.contentType = ContentType.json;
      req.write(
        jsonEncode({
          'user_id': 'dan',
          'password': _password,
          'ttl_seconds': ttlSeconds,
        }),
      );
      final res = await req.close();
      final body = jsonDecode(await res.transform(utf8.decoder).join()) as Map;
      final session = body['session'] is Map ? body['session'] as Map : body;
      return (body['token'] ?? session['token']) as String;
    } finally {
      client.close();
    }
  }

  testWidgets('API key (real server): admin locked, no sign-in prompt, data '
      'screens work', (tester) async {
    if (!configured) return markTestSkipped('sandbox not configured');
    await connectVia(tester, 'Sandbox key', _apiKey);

    expect(ScrollAPI().credentialKind, CredentialKind.apiKey);
    expect(find.text('Session expired'), findsNothing);
    expect(
      find.text(
        'Admin status is unavailable; showing the public health summary.',
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('AI Usage'));
    await tester.tap(find.text('AI Usage'));
    await pumpUntilFound(tester, find.text('READ ONLY'));
    await pumpUntilFound(tester, find.text('No AI calls recorded yet.'));

    await openAdmin(tester, 'Collections');
    expect(find.text("Locked: can't list collections"), findsOneWidget);
    await pumpFor(tester, const Duration(seconds: 2));
    expect(find.text('Session expired'), findsNothing);
  });

  testWidgets('admin token (real server): admin screens unlocked', (
    tester,
  ) async {
    if (!configured) return markTestSkipped('sandbox not configured');
    await connectVia(tester, 'Sandbox admin', _adminToken);

    expect(ScrollAPI().credentialKind, CredentialKind.adminToken);
    expect(find.text('Session expired'), findsNothing);
    expect(
      find.text(
        'Admin status is unavailable; showing the public health summary.',
      ),
      findsNothing,
    );
    await openAdmin(tester, 'Collections');
    expect(find.text("Locked: can't list collections"), findsNothing);
    expect(find.text('No collections'), findsNothing);
    expect(find.text('notes'), findsWidgets); // installed by app-notes
  });

  testWidgets('password session (real server): alive = no prompt; once it '
      'expires, "Session expired" appears', (tester) async {
    if (!configured) return markTestSkipped('sandbox not configured');
    final token = await loginSession(8);
    final issued = DateTime.now();
    await connectVia(tester, 'Sandbox session', token, sessionUser: 'dan');

    expect(ScrollAPI().credentialKind, CredentialKind.session);
    expect(
      find.text('Session expired'),
      findsNothing,
      reason: 'admin routes 401 a live session; the probe must say "alive"',
    );

    // Let the real TTL run out, then touch a user-level route (403 now).
    final wait = const Duration(seconds: 9) - DateTime.now().difference(issued);
    if (!wait.isNegative) await pumpFor(tester, wait);
    await tester.ensureVisible(find.text('AI Usage'));
    await tester.tap(find.text('AI Usage'));
    await pumpUntilFound(
      tester,
      find.text('Session expired'),
      timeout: const Duration(seconds: 25),
      reason: 'expired session must be detected via 403 + /identity/session',
    );
  });

  testWidgets('Collections GUI: create → edit → delete a note via the dialogs '
      '(admin token, real server)', (tester) async {
    if (!configured) return markTestSkipped('sandbox not configured');
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final text1 = 'GUI test note $stamp';
    final text2 = 'GUI test note $stamp (edited)';

    Future<List<Map>> notesOnServer() async {
      final rows = await ScrollAPI().listAdminCollectionRecords('notes');
      return rows.whereType<Map>().toList();
    }

    Finder dialogField(String labelPart) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            (w.decoration?.labelText ?? '').toLowerCase().contains(labelPart),
      ),
    );

    await connectVia(tester, 'Sandbox admin', _adminToken);
    await openAdmin(tester, 'Collections');
    await tester.tap(find.text('notes').first);
    await pumpFor(tester, const Duration(seconds: 2));

    // Create through the schema form.
    await tester.tap(find.text('New Record'));
    await pumpUntilFound(tester, find.byType(AlertDialog));
    await tester.enterText(dialogField('content').first, text1);
    await tester.tap(find.text('Create Record'));
    await pumpFor(tester, const Duration(seconds: 3));
    final created = (await notesOnServer())
        .where((r) => r['content'] == text1)
        .toList();
    expect(created, hasLength(1), reason: 'the note reached the server');

    // The new record must be open with a working Edit button (not merely
    // the word "Edit" on screen: that was a false positive once).
    final editButton = find.ancestor(
      of: find.text('Edit'),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    );
    expect(editButton, findsOneWidget);
    expect(
      tester.widget<ButtonStyleButton>(editButton).onPressed,
      isNotNull,
      reason: 'after Create, Scroll should open the record it just made',
    );

    // Edit through the form.
    await tester.tap(find.text('Edit'));
    await pumpUntilFound(tester, find.byType(AlertDialog));
    await tester.enterText(dialogField('content').first, text2);
    await tester.tap(find.text('Save Record'));
    await pumpFor(tester, const Duration(seconds: 3));
    expect(
      (await notesOnServer()).where((r) => r['content'] == text2),
      hasLength(1),
      reason: 'the edit reached the server',
    );

    // Delete with confirmation.
    await tester.tap(find.text('Delete'));
    await pumpUntilFound(tester, find.text('Delete record?'));
    await tester.tap(find.text('Delete Record'));
    await pumpFor(tester, const Duration(seconds: 3));
    expect(
      (await notesOnServer()).where(
        (r) => r['content'] == text1 || r['content'] == text2,
      ),
      isEmpty,
      reason: 'the delete reached the server',
    );
    expect(find.text('Session expired'), findsNothing);
  });

  testWidgets('Backup GUI: "Backup Now" creates a backup on the real server', (
    tester,
  ) async {
    if (!configured) return markTestSkipped('sandbox not configured');
    await connectVia(tester, 'Sandbox admin', _adminToken);
    final before = await ScrollAPI().listBackups();
    final countBefore = ((before['body'] as Map)['backups'] as List).length;

    await openAdmin(tester, 'Backup');
    final button = find.ancestor(
      of: find.text('Backup Now'),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    );
    expect(
      tester.widget<ButtonStyleButton>(button).onPressed,
      isNotNull,
      reason: 'admin token + backups exposed: Backup Now must be enabled',
    );
    await tester.tap(find.text('Backup Now'));
    await pumpUntilFound(
      tester,
      find.text('Backup created.'),
      timeout: const Duration(seconds: 60),
    );
    final after = await ScrollAPI().listBackups();
    expect(((after['body'] as Map)['backups'] as List).length, countBefore + 1);
  });

  testWidgets(
    'Packages GUI: "Upgrade (keep data)" on app-notes keeps records',
    (tester) async {
      if (!configured) return markTestSkipped('sandbox not configured');
      await connectVia(tester, 'Sandbox admin', _adminToken);
      final marker =
          'survives upgrade ${DateTime.now().millisecondsSinceEpoch}';
      final created = await ScrollAPI().createAdminCollectionRecord('notes', {
        'content': marker,
      });
      final body = created['body'] as Map;
      final id = ((body['record'] as Map)['id']).toString();

      await openAdmin(tester, 'Packages');
      await tester.enterText(
        textFieldLabelled('Search packages...').evaluate().isNotEmpty
            ? textFieldLabelled('Search packages...')
            : find.byWidgetPredicate(
                (w) =>
                    w is TextField &&
                    w.decoration?.hintText == 'Search packages...',
              ),
        'app-notes',
      );
      await pumpFor(tester, const Duration(seconds: 1));
      final upgrade = find.text('Upgrade (keep data)');
      expect(
        upgrade,
        findsOneWidget,
        reason: 'search should leave only app-notes',
      );
      await tester.tap(upgrade);
      await pumpUntilFound(tester, find.textContaining('Upgrade '));
      await tester.tap(find.widgetWithText(FilledButton, 'Upgrade').last);
      await pumpUntilFound(
        tester,
        // Title uses the server's display name ("Notes"), not the id.
        find.text('Notes upgraded'),
        timeout: const Duration(seconds: 60),
      );

      final still = await ScrollAPI().getAdminCollectionRecord('notes', id);
      final rec = still?['record'] is Map ? still!['record'] as Map : still;
      expect(rec?['content'], marker, reason: 'the upgrade must keep the data');
      await ScrollAPI().deleteAdminCollectionRecord('notes', id);
    },
  );
}
