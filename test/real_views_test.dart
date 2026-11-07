import 'package:flutter_test/flutter_test.dart';

import 'package:dbbasic_scroll/diagram_view.dart';
import 'package:dbbasic_scroll/home_collections.dart';
import 'package:dbbasic_scroll/query_view.dart';

void main() {
  group('buildSchemaGraph (real schema shapes)', () {
    // Shapes copied from the desk's server (6707021): fields is a list,
    // relations are {collection, display_field}.
    final schemas = <Map<String, dynamic>>[
      {
        'name': 'tasks',
        'title': 'Tasks',
        'fields': [
          {'name': 'title', 'type': 'text'},
          {
            'name': 'project_id',
            'type': 'text',
            'relation': {'collection': 'projects', 'display_field': 'name'},
          },
          {
            'name': 'template_id',
            'type': 'text',
            'relation': {'collection': 'templates', 'display_field': 'name'},
          },
        ],
      },
      {
        'name': 'projects',
        'fields': [
          {'name': 'name', 'type': 'text'},
        ],
      },
      {
        'name': 'feed_posts',
        'fields': {
          'in_reply_to': {
            'type': 'text',
            'relation': {'collection': 'feed_posts'},
          },
        },
      },
      {'name': 'action', 'fields': <dynamic>[]},
    ];

    test('edges come from relation fields, including self-references', () {
      final g = buildSchemaGraph(schemas);
      expect(
        g.edges.map((e) => '${e.from}.${e.field}->${e.to}'),
        containsAll([
          'tasks.project_id->projects',
          'tasks.template_id->templates',
          'feed_posts.in_reply_to->feed_posts',
        ]),
      );
      expect(g.edges, hasLength(3));
    });

    test('relation targets without a schema are reported as missing', () {
      expect(buildSchemaGraph(schemas).missing, {'templates'});
    });

    test('connected collections sort first; namespaces are unconnected', () {
      final g = buildSchemaGraph(schemas);
      expect(g.nodes.first.name, 'tasks'); // 2 links
      expect(g.isConnected('action'), isFalse);
      expect(g.nodes.last.name, 'action');
    });
  });

  group('Query filter', () {
    final rows = <Map<String, dynamic>>[
      {'id': '1', 'title': 'Ship invoice', 'status': 'open', 'priority': 3},
      {'id': '2', 'title': 'Call bank', 'status': 'done', 'priority': '1'},
      {'id': '3', 'title': 'Fix invoice bug', 'status': 'open', 'priority': 5},
      {'id': '4', 'title': 'No status'},
    ];
    List<String> ids(List<Map<String, dynamic>> r) =>
        r.map((e) => e['id'] as String).toList();

    test('field=value is case-insensitive equality', () {
      expect(ids(runQuery(rows, filter: 'status=OPEN')), ['1', '3']);
    });

    test('conditions joined with "and" or ";" must all match', () {
      expect(ids(runQuery(rows, filter: 'status=open and priority>4')), ['3']);
      expect(ids(runQuery(rows, filter: 'title~invoice; priority<4')), ['1']);
    });

    test('numbers compare numerically even when stored as strings', () {
      expect(ids(runQuery(rows, filter: 'priority>2')), ['1', '3']);
      expect(ids(runQuery(rows, filter: 'priority<2')), ['2']);
    });

    test('bare text matches any field; != excludes', () {
      expect(ids(runQuery(rows, filter: 'bank')), ['2']);
      expect(ids(runQuery(rows, filter: 'status!=open')), ['2', '4']);
    });

    test('sorting puts missing values last in both directions', () {
      expect(ids(runQuery(rows, sortField: 'priority')), ['2', '1', '3', '4']);
      expect(ids(runQuery(rows, sortField: 'priority', descending: true)), [
        '3',
        '1',
        '2',
        '4',
      ]);
    });

    test('columns put id first; CSV escapes commas, quotes, newlines', () {
      final cols = queryColumns([
        {'title': 'a', 'id': '1'},
        {'note': 'x'},
      ]);
      expect(cols, ['id', 'title', 'note']);
      final csv = toCsv(
        [
          {'id': '1', 'title': 'a, "b"\nc'},
        ],
        ['id', 'title'],
      );
      expect(csv, 'id,title\n1,"a, ""b""\nc"');
    });
  });

  group('Home collections', () {
    test('desk apps first even when empty, then others by size', () {
      final ordered = orderCollectionCounts(const [
        CollectionCount('site_pages', 4),
        CollectionCount('notes', 0),
        CollectionCount('shell_commands', 120),
        CollectionCount('tasks', 7),
        CollectionCount('empty_thing', 0),
      ]);
      expect(ordered.map((c) => c.name), [
        'notes',
        'tasks',
        'shell_commands',
        'site_pages',
      ]);
    });

    test('titles and the one-field create fallback', () {
      expect(titleForCollection('feed_posts'), 'Feed Posts');
      expect(primaryFieldFor('notes'), 'content');
      expect(primaryFieldFor('projects'), 'name');
      expect(primaryFieldFor('tasks'), 'title');
    });
  });
}
