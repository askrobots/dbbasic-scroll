// Home-screen views and quick actions built from the connected object
// server's own record collections (used when no AskRobots platform is
// configured, e.g. the nc desk). Works with an admin token, a password
// session, or a user API key: counts come from the user-level
// /collections/{c}/records route, which all three can read.

import 'package:flutter/material.dart';

import 'api.dart';
import 'query_view.dart';
import 'schema_form.dart';
import 'server_apps.dart';
import 'server_ui.dart';
import 'view_renderer.dart';

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

  /// Opens a collection as the server's generated page (its `views` record
  /// or the schema-driven list). Without it, rows fall back to Query.
  final ServerUiNav? nav;
  final int max;
  const ServerCollectionViews({
    super.key,
    this.onNavigate,
    this.nav,
    this.max = 10,
  });

  void _open(BuildContext context, String collection) {
    final n = nav;
    if (n != null) {
      n.open(context, '/$collection', title: titleForCollection(collection));
      return;
    }
    onNavigate?.call(
      titleForCollection(collection),
      QueryView(initialCollection: collection, autoRun: true),
      _iconFor(collection),
    );
  }

  @override
  Widget build(BuildContext context) {
    final grid = TileModeScope.of(context);
    return FutureBuilder<List<Object?>>(
      future: Future.wait([
        ServerCollectionCatalog.load(),
        NavMenuCache.load(),
      ]),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: LinearProgressIndicator(minHeight: 2),
          );
        }
        final counts = snap.data![0] as List<CollectionCount>;
        final menu = snap.data![1] as NavMenu?;
        // Collections the APPS launcher already opens aren't repeated here.
        final asApps = <String>{
          for (final g in menu?.groups ?? const <NavGroup>[])
            for (final e in g.entries)
              e.path.split('/').where((x) => x.isNotEmpty).firstOrNull ?? '',
        };
        final all = counts.where((c) => !asApps.contains(c.name)).toList();
        if (counts.isEmpty) {
          return const Text(
            'This credential cannot read any collections on this server.',
            style: TextStyle(color: Colors.white54),
          );
        }
        String sub(CollectionCount c) =>
            '${c.total} record${c.total == 1 ? '' : 's'}';
        if (grid) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final c in all.take(max))
                  IconTile(
                    icon: _iconFor(c.name),
                    label: titleForCollection(c.name),
                    sub: sub(c),
                    tooltip: c.name,
                    onTap: () => _open(context, c.name),
                  ),
                IconTile(
                  icon: Icons.manage_search_outlined,
                  label: 'All data',
                  sub: '${counts.length} collections',
                  tooltip: 'Every readable collection, in Query',
                  onTap: () => onNavigate?.call(
                    'Query',
                    const QueryView(),
                    Icons.manage_search_outlined,
                  ),
                ),
              ],
            ),
          );
        }
        return Column(
          children: [
            for (final c in all.take(max))
              _row(
                context,
                icon: _iconFor(c.name),
                title: titleForCollection(c.name),
                sub: '${sub(c)} · ${c.name}',
                count: '${c.total}',
                onTap: () => _open(context, c.name),
              ),
            _row(
              context,
              icon: Icons.manage_search_outlined,
              title: 'All collections',
              sub: '${counts.length} readable collections · open Query',
              count: '${counts.length}',
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
  String collection, {
  Map<String, dynamic> fixed = const {},
}) async {
  final api = ScrollAPI();
  final schema = await _readableSchema(collection);
  if (!context.mounted) return null;
  final spec = _formSpec(schema, hide: fixed.keys.toSet());
  Map<String, dynamic>? record;
  if (spec.hasFields) {
    final result = await showSchemaRecordFormDialog(
      context,
      collection: collection,
      spec: spec,
    );
    if (result is Map<String, dynamic>) {
      // `fixed` values (e.g. the parent project) are locked, not asked for.
      record = {...result, ...fixed}..remove('id');
    }
    if (result == null) return null;
  }
  if (record == null) {
    if (!context.mounted) return null;
    final field = primaryFieldFor(collection);
    final values = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _FieldsDialog(
        title: 'New ${titleForCollection(collection).toLowerCase()}',
        fields: {field: ''},
        confirmLabel: 'Create',
      ),
    );
    final text = values?[field]?.trim() ?? '';
    if (text.isEmpty) return null;
    record = {field: text, ...fixed};
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

/// Fields the server owns: never sent in an edit. (PUT merges, so leaving
/// them out keeps them; sending a read-only one is a 400, and Scroll never
/// reassigns ownership.)
const serverOwnedFields = {'id', 'owner_id', 'created_at', 'updated_at'};

/// The part of [record] an edit may send: drops server-owned fields and any
/// the schema marks read-only.
Map<String, dynamic> editablePayload(
  Map<String, dynamic> record, {
  Set<String> readOnly = const {},
}) => {
  for (final e in record.entries)
    if (!serverOwnedFields.contains(e.key) && !readOnly.contains(e.key))
      e.key: e.value,
};

/// The member-level /api/schema first (an API key can read it), then the
/// admin and legacy routes.
Future<Map<String, dynamic>?> _readableSchema(String collection) =>
    fetchSchemaDoc(collection);

/// The schema form minus fields a person never types: server-owned ones
/// (id, owner_id, timestamps; the server stamps them) and [hide].
SchemaFormSpec _formSpec(
  Map<String, dynamic>? schema, {
  Set<String> hide = const {},
}) {
  final spec = SchemaFormSpec.fromSchema(schema);
  return SchemaFormSpec(
    fields: [
      for (final f in spec.fields)
        if (!serverOwnedFields.contains(f.name) && !hide.contains(f.name)) f,
    ],
    listMode: spec.listMode,
    listFields: spec.listFields,
  );
}

void _toast(BuildContext context, String text) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

bool _ok(Map<String, dynamic> res) {
  final s = res['status'];
  return s is int && s >= 200 && s < 300;
}

String _why(Map<String, dynamic> res) {
  final body = res['body'];
  final detail = body is Map && body['error'] != null
      ? ': ${body['error']}'
      : '';
  return '${httpFailure(res['status'], res['error'])}$detail';
}

/// Edit [record] in [collection]. Uses the schema form when the schema is
/// readable, else a field-by-field editor built from the record itself
/// (an API key can't read schemas). Returns true when saved.
Future<bool> editServerRecord(
  BuildContext context,
  String collection,
  Map<String, dynamic> record,
) async {
  final id = record['id']?.toString() ?? '';
  if (id.isEmpty) return false;
  final schema = await _readableSchema(collection);
  if (!context.mounted) return false;
  final spec = _formSpec(schema);
  Map<String, dynamic>? changes;
  if (spec.hasFields) {
    final result = await showSchemaRecordFormDialog(
      context,
      collection: collection,
      spec: spec,
      initial: record,
    );
    if (result == null) return false;
    if (result is Map<String, dynamic>) {
      changes = editablePayload(
        result,
        readOnly: {
          for (final f in spec.fields)
            if (f.readOnly) f.name,
        },
      );
    }
  }
  if (changes == null) {
    if (!context.mounted) return false;
    changes = await _genericEditDialog(context, collection, record);
    if (changes == null) return false;
  }
  final res = await ScrollAPI().putUserCollectionRecord(
    collection,
    id,
    changes,
  );
  if (!context.mounted) return false;
  _toast(context, _ok(res) ? 'Saved' : 'Save failed (${_why(res)})');
  return _ok(res);
}

Future<Map<String, dynamic>?> _genericEditDialog(
  BuildContext context,
  String collection,
  Map<String, dynamic> record,
) async {
  final editable = editablePayload(record);
  final before = {
    for (final e in editable.entries)
      e.key: e.value == null ? '' : '${e.value}',
  };
  final after = await showDialog<Map<String, String>>(
    context: context,
    builder: (_) => _FieldsDialog(
      title: 'Edit ${titleForCollection(collection).toLowerCase()}',
      fields: before,
      confirmLabel: 'Save Record',
    ),
  );
  if (after == null) return null;
  return {
    // Only send what changed (PUT merges).
    for (final e in after.entries)
      if (e.value != before[e.key]) e.key: e.value.isEmpty ? null : e.value,
  };
}

/// A dialog of labelled text fields; returns their values, or null on
/// cancel. Owns its controllers (disposing them while the dialog is still
/// animating closed throws).
class _FieldsDialog extends StatefulWidget {
  final String title;
  final Map<String, String> fields;
  final String confirmLabel;
  const _FieldsDialog({
    required this.title,
    required this.fields,
    required this.confirmLabel,
  });

  @override
  State<_FieldsDialog> createState() => _FieldsDialogState();
}

class _FieldsDialogState extends State<_FieldsDialog> {
  late final Map<String, TextEditingController> _c = {
    for (final e in widget.fields.entries)
      e.key: TextEditingController(text: e.value),
  };

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, e) in _c.entries.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: e.value,
                    autofocus: i == 0,
                    maxLines: e.key == 'content' || e.key == 'description'
                        ? 5
                        : 1,
                    decoration: InputDecoration(
                      labelText: e.key,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            context,
          ).pop({for (final e in _c.entries) e.key: e.value.text}),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// Delete after confirmation. Returns true when deleted.
Future<bool> deleteServerRecord(
  BuildContext context,
  String collection,
  String id,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Delete record?'),
      content: Text(
        'DELETE /collections/$collection/records/$id\n\n'
        'The delete is recorded in the collection change history.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(d).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.of(d).pop(true),
          child: const Text('Delete Record'),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  final res = await ScrollAPI().deleteUserCollectionRecord(collection, id);
  if (!context.mounted) return false;
  _toast(context, _ok(res) ? 'Deleted' : 'Delete failed (${_why(res)})');
  if (_ok(res)) ServerCollectionCatalog.load(refresh: true);
  return _ok(res);
}

/// A record's fields with Edit / Delete. Returns true if it changed.
Future<bool> showServerRecord(
  BuildContext context,
  String collection,
  Map<String, dynamic> record,
) async {
  final id = record['id']?.toString() ?? '';
  final action = await showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(
        record['title']?.toString() ??
            record['name']?.toString() ??
            '${titleForCollection(collection)} $id',
        overflow: TextOverflow.ellipsis,
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final e in record.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 120,
                        child: Text(
                          e.key,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(
                        child: SelectableText(
                          e.value == null ? '' : '${e.value}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          onPressed: id.isEmpty ? null : () => Navigator.of(d).pop('delete'),
          child: const Text('Delete'),
        ),
        TextButton(
          onPressed: () => Navigator.of(d).pop(),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: id.isEmpty ? null : () => Navigator.of(d).pop('edit'),
          icon: const Icon(Icons.edit, size: 16),
          label: const Text('Edit'),
        ),
      ],
    ),
  );
  if (!context.mounted) return false;
  if (action == 'edit') return editServerRecord(context, collection, record);
  if (action == 'delete') return deleteServerRecord(context, collection, id);
  return false;
}
