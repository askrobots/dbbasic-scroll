// The server's generative UI drawn natively by Scroll, against the REAL
// object server code (local sandbox of the desk, tool/desk_sandbox.sh):
// the apps launcher, `views` records, schema-driven lists (table / board /
// cards), detail pages with related blocks, and every block kind.
//
//   tool/desk_sandbox.sh start        (SESSION_ADMIN=1 optional)
//   tool/ui_test.sh genui
//
// Uses an API key (what's hardest: no admin routes) and in-memory prefs.
// Everything it creates is deleted again with the admin token.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dbbasic_scroll/api.dart';
import 'package:dbbasic_scroll/command_box.dart';
import 'package:dbbasic_scroll/main.dart';
import 'package:dbbasic_scroll/server_apps.dart';
import 'package:dbbasic_scroll/server_profiles.dart';
import 'package:dbbasic_scroll/server_ui.dart';
import 'package:dbbasic_scroll/view_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/harness.dart';

const _url = String.fromEnvironment(
  'SANDBOX_URL',
  defaultValue: 'http://127.0.0.1:18101/',
);
const _apiKey = String.fromEnvironment('SANDBOX_API_KEY');
const _adminToken = String.fromEnvironment('SANDBOX_ADMIN_TOKEN');

/// Direct HTTP as the admin token, for setup/cleanup/verification only.
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

Future<List<Map>> records(String collection) async {
  final r = await admin(
    'GET',
    'admin/collections/$collection/records?limit=500',
  );
  return ((r['body'] as Map)['records'] as List).whereType<Map>().toList();
}

Finder dialogField(String labelPart) => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.byWidgetPredicate(
    (w) =>
        w is TextField &&
        (w.decoration?.labelText ?? '').toLowerCase().contains(labelPart),
  ),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final configured = _apiKey.isNotEmpty && _adminToken.isNotEmpty;
  final shotKey = GlobalKey();
  final outDir = Directory('${Directory.systemTemp.path}/scroll_genui');

  // Sandbox data only: safe to look at.
  Future<void> shot(WidgetTester tester, String name) async {
    await pumpFor(tester, const Duration(milliseconds: 800));
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

  setUp(resetAppState);
  tearDown(resetAppState);

  testWidgets('apps launcher → Projects → new project → its page (related '
      'blocks) → add a task to it → move the task on the Tasks board', (
    tester,
  ) async {
    if (!configured) return markTestSkipped('sandbox not configured');
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final projectName = 'GenUI project $stamp';
    final taskTitle = 'GenUI task $stamp';
    String? projectId;
    String? taskId;
    addTearDown(() async {
      if (taskId != null)
        await admin('DELETE', 'admin/collections/tasks/records/$taskId');
      if (projectId != null) {
        await admin('DELETE', 'admin/collections/projects/records/$projectId');
      }
    });

    useLaptopSurface(tester);
    await ServerProfileStore().upsert(
      ServerProfile(
        id: ServerProfile.idForUrl(_url),
        name: 'Sandbox key',
        objectServerUrl: _url,
        token: _apiKey,
      ),
    );
    await tester.pumpWidget(
      RepaintBoundary(key: shotKey, child: const ScrollApp()),
    );
    await pumpUntilFound(tester, find.text('Sandbox key'));
    await tester.tap(find.text('Sandbox key'));
    await pumpUntilFound(tester, find.text('APPS'));

    // The launcher shows the server's apps (not its own "/" Home door).
    final apps = find.byType(ServerAppsSection);
    Finder app(String label) =>
        find.descendant(of: apps, matching: find.text(label));
    for (final label in [
      'Shell',
      'Talk',
      'Notes',
      'Tasks',
      'Projects',
      'Files',
    ]) {
      expect(app(label), findsOneWidget, reason: '$label app tile');
    }
    expect(app('Home'), findsNothing);
    await shot(tester, '1_home_apps');
    await tester.ensureVisible(find.text('VIEWS'));
    await shot(tester, '2_home_views_grid');

    // Icons ⇄ list toggle for VIEWS.
    await tester.ensureVisible(find.byTooltip('Show as a list'));
    await tester.tap(find.byTooltip('Show as a list'));
    await pumpUntilFound(tester, find.text('Needs a platform URL (AskRobots)'));
    await tester.tap(find.byTooltip('Show as icons'));
    await pumpUntilFound(tester, find.byTooltip('Show as a list'));

    // Projects: its views record (list block, table mode).
    await tester.ensureVisible(app('Projects'));
    await tester.tap(app('Projects'));
    await pumpUntilFound(tester, find.text('New Project'));
    await tester.tap(find.text('New Project'));
    await pumpUntilFound(tester, dialogField('name'));
    expect(
      dialogField('owner'),
      findsNothing,
      reason: 'server-owned field hidden',
    );
    await tester.enterText(dialogField('name').first, projectName);
    await tester.tap(find.text('Create Record'));
    await pumpUntilGone(tester, find.byType(AlertDialog));
    await pumpUntilFound(tester, find.text(projectName));
    await shot(tester, '3_projects_table');
    projectId = (await records(
      'projects',
    )).firstWhere((r) => r['name'] == projectName)['id']?.toString();
    expect(projectId, isNotNull);

    // Its page: the "Project" view (detail + related Tasks/Notes/Files).
    await tester.tap(find.text(projectName));
    await pumpUntilFound(tester, find.text('Add Task'));
    await shot(tester, '4_project_page');
    expect(find.text('Tasks'), findsWidgets);
    expect(find.text('Notes'), findsWidgets);
    expect(find.text('Edit'), findsOneWidget);

    // Add a task from the related block: project_id is fixed, not asked.
    await tester.tap(find.text('Add Task'));
    await pumpUntilFound(tester, dialogField('title'));
    expect(dialogField('project'), findsNothing, reason: 'fixed by the page');
    await tester.enterText(dialogField('title').first, taskTitle);
    await tester.tap(find.text('Create Record'));
    await pumpUntilGone(tester, find.byType(AlertDialog));
    await pumpUntilFound(tester, find.text(taskTitle));
    final task = (await records(
      'tasks',
    )).firstWhere((r) => r['title'] == taskTitle);
    taskId = '${task['id']}';
    expect(
      task['project_id'],
      projectId,
      reason: 'the task belongs to the project',
    );

    // Back to Home, open Tasks: a board grouped by status.
    await tester.tap(find.byTooltip('Back'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    await tester.tap(find.byTooltip('Back'));
    await pumpUntilFound(tester, find.text('APPS'));
    await tester.ensureVisible(app('Tasks'));
    await tester.tap(app('Tasks'));
    await pumpUntilFound(tester, find.text(taskTitle));
    await shot(tester, '5_tasks_board');
    expect(find.text('Board'), findsOneWidget, reason: 'Board ⇄ Table toggle');

    final card = find.ancestor(
      of: find.text(taskTitle),
      matching: find.byType(Card),
    );
    await tester.tap(
      find.descendant(of: card, matching: find.byTooltip('Move to…')),
    );
    await pumpUntilFound(tester, find.text('Move to assigned'));
    await tester.tap(find.text('Move to assigned'));
    await pumpUntilFound(tester, find.text('Moved to assigned'));
    final moved = (await records(
      'tasks',
    )).firstWhere((r) => '${r['id']}' == taskId);
    expect(moved['status'], 'assigned', reason: 'the move reached the server');
    expect(find.text('Session expired'), findsNothing);
  });

  testWidgets('every block kind renders, and a broken block never breaks the '
      'page', (tester) async {
    if (!configured) return markTestSkipped('sandbox not configured');
    final note = await admin('POST', 'admin/collections/notes/records', {
      'content': 'block test note',
    });
    final noteId = '${((note['body'] as Map)['record'] as Map)['id']}';
    addTearDown(
      () => admin('DELETE', 'admin/collections/notes/records/$noteId'),
    );

    final blocks = [
      {'kind': 'markdown', 'text': 'Hello **bold** world\n\nSecond *para*'},
      {'kind': 'count', 'collection': 'unit_prices', 'label': 'Price rows'},
      {
        'kind': 'aggregate',
        'collection': 'unit_prices',
        'sums': ['unit_price_cents'],
        'title': 'Price totals',
      },
      {
        'kind': 'list',
        'collection': 'notes',
        'filters': {'content': 'block test note'},
        'limit': 2,
        'title': 'Filtered notes',
      },
      {'kind': 'detail', 'collection': 'notes', 'record_id': noteId},
      {'kind': 'form', 'collection': 'notes', 'title': 'Quick note'},
      {'kind': 'thread', 'collection': 'notes', 'record_id': noteId},
      {'kind': 'object', 'object_id': 'site_custom', 'title': 'Custom panel'},
      {
        'kind': 'related',
        'collection': 'tasks',
        'fk_field': 'project_id',
        'match': r'$record_id',
      },
      {'kind': 'sparkle'},
    ];

    useLaptopSurface(tester, size: const Size(1440, 2400));
    expect(
      await ScrollAPI().connect(objectServerUrl: _url, token: _apiKey),
      isTrue,
    );
    final view = ServerView.from({
      'id': 'test',
      'title': 'Block test',
      'route': '/block-test',
      'layout': 'single',
      'blocks': jsonEncode(blocks),
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: ServerViewPage(view: view, nav: const ServerUiNav()),
        ),
      ),
    );
    await pumpUntilFound(tester, find.text('Price totals'));
    await pumpFor(tester, const Duration(seconds: 2));

    expect(
      find.byWidgetPredicate(
        (w) =>
            w is SelectableText &&
            (w.textSpan?.toPlainText() ?? '').contains('Hello bold world'),
      ),
      findsOneWidget,
      reason: 'markdown: bold markers rendered, not shown',
    );
    expect(find.text('Price rows'), findsOneWidget);
    expect(find.text('5'), findsWidgets, reason: 'count of unit_prices');
    expect(find.text('Unit Price'), findsOneWidget, reason: 'aggregate label');
    expect(find.text('Filtered notes'), findsOneWidget);
    expect(find.text('block test note'), findsWidgets, reason: 'list + detail');
    expect(find.text('Quick note'), findsOneWidget);
    expect(
      find.text("Comments aren't installed on this server."),
      findsOneWidget,
    );
    expect(
      find.text('PLANNED'),
      findsWidgets,
      reason: 'object block is planned',
    );
    expect(find.text("related block's match did not resolve"), findsOneWidget);
    expect(find.text('Unsupported block kind: sparkle'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('command box: ⌘K, / commands with Tab, a note saved through '
      'the server, live search → open the hit, ⌘↵ Find', (tester) async {
    if (!configured) return markTestSkipped('sandbox not configured');
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final noteText = 'Boxnote$stamp from the command box';
    addTearDown(() async {
      for (final r in await records('notes')) {
        if ('${r['content']}'.startsWith('Boxnote$stamp')) {
          await admin('DELETE', 'admin/collections/notes/records/${r['id']}');
        }
      }
    });

    useLaptopSurface(tester);
    await ServerProfileStore().upsert(
      ServerProfile(
        id: ServerProfile.idForUrl(_url),
        name: 'Sandbox key',
        objectServerUrl: _url,
        token: _apiKey,
      ),
    );
    await tester.pumpWidget(
      RepaintBoundary(key: shotKey, child: const ScrollApp()),
    );
    await pumpUntilFound(tester, find.text('Sandbox key'));
    await tester.tap(find.text('Sandbox key'));
    await pumpUntilFound(tester, find.text('APPS'));

    final box = find.byKey(const Key('command-box'));
    String boxText() => tester.widget<TextField>(box).controller!.text;

    // ⌘K from anywhere focuses the box and opens Quick start.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await pumpUntilFound(tester, find.text('QUICK START'));
    expect(find.text('all ${boxCommands.length} commands'), findsOneWidget);
    await shot(tester, '6_box_quick_start');

    // "/" lists commands; links isn't installed here, so /link is greyed.
    await tester.enterText(box, '/');
    await pumpUntilFound(tester, find.text('/link'));
    await pumpUntilFound(
      tester,
      find.textContaining('not installed on this server'),
    );
    await shot(tester, '7_box_commands');

    // Partial word + Tab completes; Enter runs it as the signed-in user.
    await tester.enterText(box, '/no');
    await pumpUntilFound(tester, find.text('save a private note'));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(boxText(), '/note ');
    await tester.enterText(box, '/note $noteText');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await pumpUntilFound(tester, find.text('Note saved'));
    final saved = (await records(
      'notes',
    )).where((r) => r['content'] == noteText).toList();
    expect(saved, hasLength(1), reason: 'the note reached the server');
    expect(saved.single['owner_id'], 'dan', reason: 'server-stamped owner');
    expect(saved.single['is_public'], 'false');

    // Plain text: live search; the hit opens the note's page.
    await tester.tap(box);
    await tester.enterText(box, 'Boxnote$stamp');
    await pumpUntilFound(tester, find.text('NOTES'));
    expect(
      find.descendant(
        of: find.byKey(const Key('command-box-dropdown')),
        matching: find.text('Ask AI'),
      ),
      findsNWidgets(2),
      reason: 'the Ask AI row + the Enter legend',
    );
    await shot(tester, '8_box_search');
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('command-box-dropdown')),
        // The hit row (Ask AI / Find rows only echo the typed words).
        matching: find.textContaining('from the command box'),
      ),
    );
    await pumpUntilFound(tester, find.text('Edit'));
    expect(find.text(noteText), findsWidgets);

    // ⌘↵ = Find: the Search screen, already searched.
    await tester.tap(box);
    await tester.enterText(box, 'Boxnote$stamp');
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await pumpUntilFound(tester, find.byType(GlobalSearchView));
    await pumpUntilFound(
      tester,
      find.descendant(
        of: find.byType(GlobalSearchView),
        matching: find.textContaining('Boxnote$stamp'),
      ),
    );

    // Esc closes the dropdown.
    await tester.tap(box);
    await pumpUntilFound(tester, find.byKey(const Key('command-box-dropdown')));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpUntilGone(tester, find.byKey(const Key('command-box-dropdown')));
    expect(find.text('Session expired'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
