import 'package:flutter_test/flutter_test.dart';

import 'package:dbbasic_scroll/server_ui.dart';

void main() {
  group('launcher (nav_entries)', () {
    test('action_nav_entries answer → groups; zero attention is dropped', () {
      final menu = parseNavMenu({
        'ok': true,
        'groups': [
          {
            'group': 'Work',
            'entries': [
              {'label': 'Notes', 'path': '/notes', 'blurb': 'Quick capture'},
              {'label': 'Tasks', 'path': '/tasks', 'count': 3},
            ],
          },
        ],
        'attention': [
          {
            'label': 'Review',
            'path': '/review',
            'count': 2,
            'severity': 'urgent',
          },
          {'label': 'Quiet', 'path': '/quiet', 'count': 0},
        ],
      });
      expect(menu.groups.single.group, 'Work');
      expect(menu.groups.single.entries.map((e) => e.label), [
        'Notes',
        'Tasks',
      ]);
      expect(menu.groups.single.entries[1].count, 3);
      expect(menu.attention.map((a) => a.label), ['Review']);
    });

    test('raw rows fallback: grouped, ordered, hidden doors dropped', () {
      final menu = navMenuFromRows([
        {'label': 'Tasks', 'path': '/tasks', 'group': 'Work', 'order': '40'},
        {'label': 'Notes', 'path': '/notes', 'group': 'Work', 'order': 30},
        {'label': 'Secret', 'path': '/x', 'group': 'Work', 'surface': 'hidden'},
        {'label': 'Books', 'path': '/journals', 'group': 'Money', 'order': 1},
      ]);
      expect(menu.groups.map((g) => g.group), ['Work', 'Money']);
      expect(menu.groups.first.entries.map((e) => e.label), ['Notes', 'Tasks']);
    });
  });

  group('views', () {
    // The seeded app-views records on 6707021.
    final views = [
      ServerView.from({
        'id': 'v1',
        'title': 'Notes',
        'route': '/notes',
        'layout': 'single',
        'blocks':
            '[{"kind":"list","collection":"notes","search":true,"title_field":"content","add_label":"+ New Note"}]',
      }),
      ServerView.from({
        'id': 'v2',
        'title': 'Note',
        'route': '/notes/{note_id}',
        'blocks':
            '[{"kind":"detail","collection":"notes","record_id":"\$record_id"}]',
      }),
      ServerView.from({
        'id': 'v3',
        'title': 'Project',
        'route': '/projects/{project_id:uuid}',
        'blocks':
            '[{"kind":"detail","collection":"projects","record_id":"\$record_id"},'
            '{"kind":"related","collection":"tasks","fk_field":"project_id","match":"\$record_id","title":"Tasks"}]',
      }),
      ServerView.from({
        'id': 'bad',
        'title': 'Broken',
        'route': '/b',
        'blocks': '{not json',
      }),
      ServerView.from({
        'id': 'obj',
        'title': 'Obj',
        'route': '/o',
        'blocks': '{"kind":"list"}',
      }),
    ];

    test('blocks parse; malformed JSON and non-lists are reported', () {
      expect(views[0].blocks.single.kind, 'list');
      expect(views[0].blocks.single['add_label'], '+ New Note');
      expect(views[3].blocksError, 'Invalid blocks JSON');
      expect(views[4].blocksError, 'blocks must be a JSON array');
      expect(ViewBlock({'kind': 'sparkle'}).isKnown, isFalse);
    });

    test('route matching: exact first, then one capture as \$record_id', () {
      expect(matchRoute('/notes', '/notes'), isEmpty);
      expect(matchRoute('/notes/{note_id}', '/notes/abc'), {'note_id': 'abc'});
      expect(matchRoute('/projects/{project_id:uuid}', '/projects/p1'), {
        'project_id': 'p1',
      });
      expect(matchRoute('/notes/{id}', '/notes'), isNull);
      expect(matchRoute('/notes', '/tasks'), isNull);
      expect(matchRoute('/notes/', '/notes'), isEmpty);

      expect(findViewForPath(views, '/notes')!.view.id, 'v1');
      final note = findViewForPath(views, '/notes/n42')!;
      expect(note.view.id, 'v2');
      expect(note.recordId, 'n42');
      expect(findViewForPath(views, '/files'), isNull);
    });

    test('\$record_id resolves to the captured id, or null without one', () {
      final related = views[2].blocks[1];
      expect(related.resolved('match', 'p1'), 'p1');
      expect(related.resolved('match', null), isNull);
      expect(related.resolved('fk_field', 'p1'), 'project_id');
    });

    test('generated pages for collections without a views record', () {
      final list = ServerView.listFor('feed_posts');
      expect(list.title, 'Feed Posts');
      expect(list.blocks.single.kind, 'list');
      expect(ServerView.detailFor('categories').title, 'Category');
    });
  });

  group('schema layout hints', () {
    // app-tasks' real schema shape (abridged).
    final tasks = SchemaUi.from({
      'fields': [
        {'name': 'id'},
        {'name': 'title', 'type': 'text'},
        {
          'name': 'task_type',
          'type': 'enum',
          'enum': ['BASIC', 'STANDARD'],
        },
        {
          'name': 'status',
          'type': 'enum',
          'enum': ['open', 'assigned', 'done'],
          'transitions': {
            'open': ['assigned'],
            'assigned': ['done', 'open'],
          },
        },
        {'name': 'owner_id'},
        {'name': 'created_at', 'type': 'datetime', 'read_only': true},
      ],
      'forms': {
        'default': {
          'fields': ['title', 'status', 'task_type'],
        },
      },
      'views': {
        'list_mode': 'board',
        'list_fields': ['title', 'status'],
        'filter_fields': ['status'],
        'detail_fields': ['title', 'status', 'id', 'owner_id'],
      },
      'capabilities': {'comments': true},
      'search': {
        'fields': ['title'],
      },
    });

    test('snake_case keys are read', () {
      expect(tasks.listMode, 'board');
      expect(tasks.listFields, ['title', 'status']);
      expect(tasks.filterFields, ['status']);
      expect(tasks.formFields, ['title', 'status', 'task_type']);
      expect(tasks.capabilities['comments'], isTrue);
      expect(tasks.searchable, isTrue);
    });

    test(
      'board groups by the transitions-guarded enum, not the first enum',
      () {
        expect(tasks.boardField, 'status');
        final withFlow = SchemaUi.from({
          'fields': [
            {
              'name': 'a',
              'type': 'enum',
              'enum': ['x'],
            },
            {
              'name': 'b',
              'type': 'enum',
              'enum': ['y'],
            },
          ],
          'flow': {'field': 'b'},
        });
        expect(withFlow.boardField, 'b');
        expect(SchemaUi.from({'fields': []}).boardField, isNull);
      },
    );

    test('guarded transitions ({to, when}) offer their target state', () {
      // app-tasks' real shape: plain strings mixed with guarded moves.
      final s = SchemaUi.from({
        'fields': [
          {
            'name': 'status',
            'type': 'enum',
            'enum': ['draft', 'open', 'assigned', 'cancelled'],
            'transitions': {
              'open': [
                'assigned',
                {
                  'to': 'cancelled',
                  'when': {'owner_id': '\$user_id'},
                },
              ],
            },
          },
        ],
      });
      expect(s.field('status')!.allowedEnumValues('open'), [
        'open',
        'assigned',
        'cancelled',
      ]);
      // A state missing from the map is terminal.
      expect(s.field('status')!.allowedEnumValues('cancelled'), ['cancelled']);
    });

    test('detail order drops server-owned plumbing', () {
      expect(tasks.detailOrder, ['title', 'status']);
    });
  });

  group('display rules', () {
    final now = DateTime.utc(2026, 11, 6, 12);

    test('rowLabel never shows an id; skips id- and date-shaped strings', () {
      expect(rowLabel({'id': 'x', 'title': 'Ship it'}), 'Ship it');
      expect(
        rowLabel({
          'id': '0549777e-471d-4eb0-a574-d8c658092ad6',
          'created_at': '2026-11-06T00:00:00Z',
          'content': '  buy   more\ncables ',
        }),
        'buy more cables',
      );
      expect(rowLabel({'id': 'x', 'project_id': 'p'}), '(untitled)');
      expect(rowLabel({'path': '/a'}, titleField: 'path'), '/a');
      expect(rowLabel({}, titleField: 'path'), '(none)');
    });

    test('values format like the web: cents, booleans, relations, dates', () {
      final t = SchemaUi.from({
        'fields': [
          {'name': 'is_public', 'type': 'boolean'},
          {
            'name': 'project_id',
            'relation': {'collection': 'projects', 'display_field': 'name'},
          },
          {'name': 'due', 'type': 'datetime'},
        ],
      });
      expect(formatValue('total_cents', null, 123456), '\$1234.56');
      expect(formatValue('total_cents', null, '-5'), '-\$0.05');
      expect(formatValue('is_public', t.field('is_public'), 'true'), 'Yes');
      expect(formatValue('is_public', t.field('is_public'), 'false'), 'No');
      expect(
        formatValue(
          'project_id',
          t.field('project_id'),
          'p1',
          relationLabels: {'p1': 'Garden'},
        ),
        'Garden',
      );
      expect(
        formatValue(
          'project_id',
          t.field('project_id'),
          'gone',
          relationLabels: {},
        ),
        'gone',
      );
      expect(
        formatValue('created_at', null, '2026-11-06T09:00:00Z', now: now),
        '3h ago',
      );
      expect(
        formatValue('due', t.field('due'), '2026-11-08T12:00:00Z', now: now),
        'in 2d',
      );
      expect(formatValue('note', null, null), '');
    });

    test('singular and title case match the web renderer', () {
      expect(singular('tasks'), 'Task');
      expect(singular('categories'), 'Category');
      expect(singular('feed_posts'), 'Feed Post');
      expect(titleCaseName('ai_usage'), 'Ai Usage');
    });
  });
}
