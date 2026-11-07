// Home-screen views and quick actions built from the connected object
// server's own record collections (used when no AskRobots platform is
// configured, e.g. the nc desk). Works with an admin token, a password
// session, or a user API key: counts come from the user-level
// /collections/{c}/records route, which all three can read.

import 'package:flutter/material.dart';

import 'api.dart';
import 'query_view.dart';
import 'schema_form.dart';

/// The desk apps' collections, shown first and offered as quick actions.
const preferredCollections = [
  'notes',
  'tasks',
  'projects',
  'notifications',
  'feed_posts',
  'files',
];

class CollectionCount {
  final String name;
  final int total;
  const CollectionCount(this.name, this.total);
}

/// Order for the Views list: preferred apps first (in that order, even when
/// empty), then other collections that have records, largest first.
List<CollectionCount> orderCollectionCounts(List<CollectionCount> counts) {
  final byName = {for (final c in counts) c.name: c};
  final preferred = [
    for (final n in preferredCollections)
      if (byName[n] != null) byName[n]!,
  ];
  final rest =
      counts
          .where((c) => !preferredCollections.contains(c.name) && c.total > 0)
          .toList()
        ..sort((a, b) {
          final d = b.total.compareTo(a.total);
          return d != 0 ? d : a.name.compareTo(b.name);
        });
  return [...preferred, ...rest];
}

String titleForCollection(String name) => name
    .split('_')
    .where((p) => p.isNotEmpty)
    .map((p) => '${p[0].toUpperCase()}${p.substring(1)}')
    .join(' ');

class ServerCollectionCatalog {
  static Future<List<CollectionCount>>? _pending;
  static String? _forUrl;

  /// Cached per server; [refresh] forces a reload.
  static Future<List<CollectionCount>> load({bool refresh = false}) {
    final url = ScrollAPI().objectServerUrl;
    if (refresh || _pending == null || _forUrl != url) {
      _forUrl = url;
      _pending = _load();
    }
    return _pending!;
  }

  static Future<List<CollectionCount>> _load() async {
    final api = ScrollAPI();
    final listed = await api.listAdminCollections();
    final names = listed.isEmpty
        // A user key can't list collections; probe the desk apps instead.
        ? [...preferredCollections, 'ai_usage', 'task_comments']
        : [
            for (final c in listed)
              if (c is Map &&
                  (c['has_records'] != false || c['has_schema'] != false))
                (c['name'] ?? '').toString(),
          ].where((n) => n.isNotEmpty).toList();
    final counts = await Future.wait(
      names.map((n) async {
        final r = await api.rawRequest(
          'GET',
          '${api.objectServerUrl}collections/${Uri.encodeComponent(n)}/records?limit=1',
        );
        final body = r['body'];
        if (r['status'] != 200 || body is! Map) return null;
        return CollectionCount(n, (body['total'] as num?)?.toInt() ?? 0);
      }),
    );
    return orderCollectionCounts(counts.whereType<CollectionCount>().toList());
  }
}

IconData _iconFor(String name) => switch (name) {
  'notes' => Icons.sticky_note_2_outlined,
  'tasks' => Icons.check_circle_outline,
  'projects' => Icons.folder_outlined,
  'notifications' => Icons.notifications_none,
  'feed_posts' => Icons.dynamic_feed_outlined,
  'files' => Icons.insert_drive_file_outlined,
  'ai_usage' => Icons.paid_outlined,
  _ => Icons.table_rows_outlined,
};

typedef NavigateFn = void Function(String, Widget, [IconData]);

/// "VIEWS" rows for the server's collections.
class ServerCollectionViews extends StatelessWidget {
  final NavigateFn? onNavigate;
  final int max;
  const ServerCollectionViews({super.key, this.onNavigate, this.max = 10});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CollectionCount>>(
      future: ServerCollectionCatalog.load(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: LinearProgressIndicator(minHeight: 2),
          );
        }
        final all = snap.data!;
        if (all.isEmpty) {
          return const Text(
            'This credential cannot read any collections on this server.',
            style: TextStyle(color: Colors.white54),
          );
        }
        return Column(
          children: [
            for (final c in all.take(max))
              _row(
                context,
                icon: _iconFor(c.name),
                title: titleForCollection(c.name),
                sub: '${c.total} record${c.total == 1 ? '' : 's'} · ${c.name}',
                count: '${c.total}',
                onTap: () => onNavigate?.call(
                  titleForCollection(c.name),
                  QueryView(initialCollection: c.name, autoRun: true),
                  _iconFor(c.name),
                ),
              ),
            if (all.length > max)
              _row(
                context,
                icon: Icons.manage_search_outlined,
                title: 'All collections',
                sub: '${all.length} readable collections · open Query',
                count: '${all.length}',
                onTap: () => onNavigate?.call(
                  'Query',
                  const QueryView(),
                  Icons.manage_search_outlined,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _row(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String sub,
    required String count,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        child: Row(
          children: [
            Icon(icon, size: 24, color: Colors.white60),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 15)),
                  Text(
                    sub,
                    style: const TextStyle(fontSize: 12, color: Colors.white38),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(count, style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The field a one-box create dialog fills when no schema is readable.
String primaryFieldFor(String collection) => switch (collection) {
  'notes' => 'content',
  'projects' => 'name',
  _ => 'title',
};

/// Create a record in [collection] through the object server: the schema
/// form when the schema is readable, otherwise a one-field dialog.
/// Returns the created record id, or null if cancelled/failed.
Future<String?> createServerRecord(
  BuildContext context,
  String collection,
) async {
  final api = ScrollAPI();
  final schema =
      await api.getAdminSchema(collection) ?? await api.getSchema(collection);
  if (!context.mounted) return null;
  final spec = SchemaFormSpec.fromSchema(schema);
  Map<String, dynamic>? record;
  if (spec.hasFields) {
    final result = await showSchemaRecordFormDialog(
      context,
      collection: collection,
      spec: spec,
    );
    if (result is Map<String, dynamic>) record = result;
    if (result == null) return null;
  }
  if (record == null) {
    if (!context.mounted) return null;
    final field = primaryFieldFor(collection);
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('New ${titleForCollection(collection).toLowerCase()}'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLines: field == 'content' ? 6 : 1,
            decoration: InputDecoration(
              labelText: field,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(d).pop(true),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    final text = controller.text.trim();
    controller.dispose();
    if (ok != true || text.isEmpty) return null;
    record = {field: text};
  }
  final res = await api.createUserCollectionRecord(collection, record);
  final status = res['status'];
  final body = res['body'];
  final ok = status is int && status >= 200 && status < 300;
  final id = ok && body is Map && body['record'] is Map
      ? (body['record'] as Map)['id']?.toString()
      : null;
  if (context.mounted) {
    final detail = body is Map && body['error'] != null
        ? ': ${body['error']}'
        : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Created in $collection'
              : 'Create failed (${httpFailure(status, res['error'])})$detail',
        ),
      ),
    );
  }
  if (ok) ServerCollectionCatalog.load(refresh: true);
  return id;
}
