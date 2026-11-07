// Hermetic UI tests: drive the real app (taps, typing, reading the screen)
// against an in-process fake object server. No credentials, no real servers,
// no touching the developer's saved connections.
//
// Run:  tool/ui_test.sh        (or: flutter test integration_test/connect_flow_test.dart -d macos)

import 'package:dbbasic_scroll/main.dart';
import 'package:dbbasic_scroll/server_profiles.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/fake_object_server.dart';
import 'support/harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late FakeObjectServer server;

  Future<void> startApp(WidgetTester tester) async {
    useLaptopSurface(tester);
    await tester.pumpWidget(const ScrollApp());
    await pumpUntilFound(
      tester,
      find.text('Connect to your object server'),
      reason: 'Connect screen should appear with no saved connection',
    );
  }

  Future<void> connectWithToken(
    WidgetTester tester, {
    required String name,
    required String token,
  }) async {
    await tester.enterText(
      textFieldLabelled('Object Server URL (required)'),
      server.url,
    );
    await tester.enterText(textFieldLabelled('Save as (optional)'), name);
    await tester.enterText(textFieldLabelled('Bearer Token'), token);
    await tester.tap(find.text('Connect'));
    await pumpUntilFound(
      tester,
      find.text('What would you like to do?'),
      reason: 'Should reach the main shell after connecting',
    );
  }

  setUp(() async {
    await resetAppState();
    server = FakeObjectServer();
    await server.start();
  });

  tearDown(() async {
    await resetAppState();
    await server.stop();
  });

  testWidgets(
    'ordinary (non-admin) credential: connects, admin parts show as locked, '
    'and no "Session expired" prompt',
    (tester) async {
      await startApp(tester);
      await connectWithToken(tester, name: 'Fake VM', token: 'dbk_test-key');
      await pumpFor(tester, const Duration(seconds: 4)); // let loadAll finish

      // The 401s from admin-gated routes must NOT be read as an expired login.
      expect(find.text('Session expired'), findsNothing);

      // ...they must read as locked instead.
      expect(
        find.text(
          'Admin status is unavailable; showing the public health summary.',
        ),
        findsOneWidget,
      );
      expect(find.text('locked'), findsWidgets);

      // The app really called the admin routes (so the test is meaningful)...
      expect(server.requested('/admin/status'), isTrue);
      expect(server.requested('/daemon/status'), isTrue);
      // ...and sent the credential as a Bearer token.
      expect(server.authHeaders, isNotEmpty);
      expect(server.authHeaders.toSet(), {'Bearer dbk_test-key'});

      // Sample numbers may appear only inside a tile marked as a mockup.
      for (final sample in [
        find.text('341'),
        find.textContaining('18 this week'),
      ]) {
        expect(sample, findsOneWidget);
        expect(
          find.ancestor(of: sample, matching: find.byType(MockupOutline)),
          findsOneWidget,
          reason: 'sample data must be labelled as a mockup',
        );
      }
    },
  );

  testWidgets('a genuinely rejected credential prompts to sign in again', (
    tester,
  ) async {
    server.credentialExpired = true; // user-level routes now 401
    await startApp(tester);
    await connectWithToken(tester, name: 'Expired', token: 'old-session');

    await pumpUntilFound(
      tester,
      find.text('Session expired'),
      reason: 'A 401 on a user-level route means the credential is dead',
    );
    expect(find.text('Sign In Again'), findsOneWidget);
  });

  testWidgets('connecting saves a profile; it can be reused and forgotten', (
    tester,
  ) async {
    await startApp(tester);
    await connectWithToken(tester, name: 'Fake VM', token: 'dbk_test-key');

    final saved = await ServerProfileStore().list();
    expect(saved, hasLength(1));
    expect(saved.single.name, 'Fake VM');
    expect(saved.single.objectServerUrl, '${server.url}/');
    // toString must never leak the credential.
    expect(saved.single.toString(), isNot(contains('dbk_test-key')));
  });

  Future<void> seedProfile() => ServerProfileStore().upsert(
    ServerProfile(
      id: ServerProfile.idForUrl(server.url),
      name: 'Seeded VM',
      objectServerUrl: ServerProfile.normaliseUrl(server.url),
      token: 'dbk_seeded-key',
    ),
  );

  testWidgets('saved connection: tapping it connects with its stored token', (
    tester,
  ) async {
    await seedProfile();
    await startApp(tester); // as after a relaunch
    await pumpUntilFound(tester, find.text('Seeded VM'));

    await tester.tap(find.text('Seeded VM'));
    await pumpUntilFound(
      tester,
      find.text('What would you like to do?'),
      reason: 'Tapping a saved connection should reach the shell',
    );
    await pumpFor(tester, const Duration(seconds: 2));
    expect(server.authHeaders.toSet(), {'Bearer dbk_seeded-key'});
    expect(find.text('Session expired'), findsNothing);
  });

  testWidgets('saved connection: the trash icon forgets it', (tester) async {
    await seedProfile();
    await startApp(tester);
    await pumpUntilFound(tester, find.text('Seeded VM'));

    await tester.tap(find.byTooltip('Forget this connection'));
    await pumpFor(tester, const Duration(milliseconds: 500));

    expect(find.text('Seeded VM'), findsNothing);
    expect(await ServerProfileStore().list(), isEmpty);
  });

  testWidgets(
    'server switcher: hop between two saved servers, each with its own token',
    (tester) async {
      final second = FakeObjectServer();
      await second.start();
      addTearDown(second.stop);

      Future<void> seed(String name, FakeObjectServer srv, String token) =>
          ServerProfileStore().upsert(
            ServerProfile(
              id: ServerProfile.idForUrl(srv.url),
              name: name,
              objectServerUrl: ServerProfile.normaliseUrl(srv.url),
              token: token,
            ),
          );
      await seed('First', server, 'dbk_key-one');
      await seed('Second', second, 'dbk_key-two');

      await startApp(tester);
      await pumpUntilFound(tester, find.text('First'));
      await tester.tap(find.text('First'));
      await pumpUntilFound(tester, find.text('What would you like to do?'));
      await pumpFor(tester, const Duration(seconds: 2));
      expect(server.authHeaders.toSet(), {'Bearer dbk_key-one'});
      expect(second.requests, isEmpty, reason: 'second is not contacted yet');

      // Switch via the app-bar switcher; no token typed.
      await tester.tap(find.byTooltip('Switch server'));
      await pumpUntilFound(tester, find.text('Second'));
      await tester.tap(find.text('Second'));
      await pumpUntilFound(
        tester,
        find.text('What would you like to do?'),
        reason: 'A fresh shell should load after switching',
      );
      await pumpFor(tester, const Duration(seconds: 3));

      expect(second.authHeaders.toSet(), {'Bearer dbk_key-two'});
      expect(find.text('Session expired'), findsNothing);

      // The old server must go quiet: nothing from the first shell lingers.
      final before = server.requests.length;
      await pumpFor(tester, const Duration(seconds: 3));
      expect(server.requests.length, before);
    },
  );

  testWidgets('AI Usage screen totals the caller\'s ai_usage rows', (
    tester,
  ) async {
    final today = DateTime.now().toIso8601String();
    server.aiUsageRows = [
      {
        'provider': 'anthropic',
        'model': 'big',
        'tokens_in': 1500,
        'tokens_out': 500,
        'cost_cents': 250,
        'created_at': today,
      },
      {
        'provider': 'anthropic',
        'model': 'big',
        'tokens_in': 500,
        'tokens_out': 100,
        'cost_cents': 150,
        'created_at': today,
      },
      {
        'provider': 'openai',
        'model': 'small',
        'tokens_in': 10,
        'tokens_out': 5,
        'cost_cents': null,
        'created_at': today,
      },
    ];
    await startApp(tester);
    await connectWithToken(tester, name: 'Fake', token: 'dbk_test-key');

    await tester.ensureVisible(find.text('AI Usage'));
    await tester.tap(find.text('AI Usage'));
    await pumpUntilFound(tester, find.text('READ ONLY'));
    await pumpUntilFound(tester, find.text('By model'));

    expect(find.text('\$4.00'), findsWidgets); // 250 + 150 cents
    expect(find.text('anthropic / big'), findsOneWidget);
    expect(find.text('openai / small'), findsOneWidget);
    expect(find.textContaining('1 call(s) had no price'), findsOneWidget);
    expect(server.requested('/collections/ai_usage/records'), isTrue);
  });

  testWidgets('AI Usage on a server without the collection says so', (
    tester,
  ) async {
    server.aiUsageRows = null; // 404
    await startApp(tester);
    await connectWithToken(tester, name: 'Fake', token: 'dbk_test-key');
    await tester.ensureVisible(find.text('AI Usage'));
    await tester.tap(find.text('AI Usage'));
    await pumpUntilFound(tester, find.textContaining('no ai_usage collection'));
  });

  for (final locked in [true, false]) {
    testWidgets(
      locked
          ? 'admin lists say "Locked" (not "No collections") for a non-admin'
          : 'admin lists say "No collections" when really empty',
      (tester) async {
        server.adminGated = locked;
        await startApp(tester);
        await connectWithToken(tester, name: 'Fake', token: 'dbk_test-key');
        await pumpFor(tester, const Duration(seconds: 2));
        await tester.tap(find.text('Admin'));
        await pumpFor(tester, const Duration(milliseconds: 500));

        await tester.tap(find.text('Collections').first);
        await pumpFor(tester, const Duration(seconds: 2));
        expect(
          find.text("Locked: can't list collections"),
          locked ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('No collections'),
          locked ? findsNothing : findsOneWidget,
        );

        await tester.tap(find.text('Schema').first);
        await pumpFor(tester, const Duration(seconds: 2));
        expect(
          find.text("Locked: can't list schemas"),
          locked ? findsOneWidget : findsNothing,
        );
      },
    );
  }
}
