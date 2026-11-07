// The object server's generative UI, read natively (logic only; widgets are
// in view_renderer.dart). The server has no per-app UI code: a collection's
// schema drives list/form/detail, `views` records compose blocks into pages,
// and `nav_entries` is the app launcher every package writes on install.
// See the server's docs/generative-ui.md and docs/schema-forms.md.
//
// Everything here reads through user-level routes, so an API key works as
// well as a session (measured on 6707021): POST /objects/action_nav_entries,
// GET /api/schema/{c}, GET /collections/{views,nav_entries,...}/records.

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'schema_form.dart';

// ---------------------------------------------------------------------------
// App launcher (nav_entries / action_nav_entries)
// ---------------------------------------------------------------------------

class NavEntry {
  final String label;
  final String path;
  final String blurb;
  final String group;
  final String package;
  final int order;

  /// Attention count ("needs you"); null when the app declares no queue.
  final int? count;
  final String severity;
  final String detail;

  const NavEntry({
    required this.label,
    required this.path,
    this.blurb = '',
    this.group = '',
    this.package = '',
    this.order = 0,
    this.count,
    this.severity = '',
    this.detail = '',
  });

  static int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v');

  factory NavEntry.from(Map raw) => NavEntry(
    label: '${raw['label'] ?? raw['path'] ?? ''}',
    path: '${raw['path'] ?? ''}',
    blurb: '${raw['blurb'] ?? ''}',
    group: '${raw['group'] ?? ''}',
    package: '${raw['package'] ?? ''}',
    order: _int(raw['order']) ?? 0,
    count: _int(raw['count']),
    severity: '${raw['severity'] ?? ''}',
    detail: '${raw['detail'] ?? ''}',
  );
}

class NavGroup {
  final String group;
  final List<NavEntry> entries;
  const NavGroup(this.group, this.entries);
}

class NavMenu {
  final List<NavGroup> groups;

  /// Queues waiting for a person, loudest first. Only non-zero ones are
  /// kept: when everything is zero the band is absent (home.py's rule).
  final List<NavEntry> attention;
  const NavMenu(this.groups, this.attention);

  bool get isEmpty => groups.every((g) => g.entries.isEmpty);
}

/// From action_nav_entries' answer ({groups: [{group, entries}], attention}).
NavMenu parseNavMenu(Map body) {
  final groups = <NavGroup>[
    for (final g in (body['groups'] as List? ?? const []).whereType<Map>())
      NavGroup('${g['group'] ?? ''}', [
        for (final e in (g['entries'] as List? ?? const []).whereType<Map>())
          NavEntry.from(e),
      ]),
  ];
  final attention = [
    for (final a in (body['attention'] as List? ?? const []).whereType<Map>())
      NavEntry.from(a),
  ].where((a) => (a.count ?? 0) > 0).toList();
  return NavMenu(groups, attention);
}

/// Fallback when the object can't be called: fold raw nav_entries rows the
/// way the registry does (group, then order), dropping hidden doors.
NavMenu navMenuFromRows(List<Map> rows) {
  final visible = rows
      .where((r) => '${r['surface'] ?? ''}' != 'hidden')
      .map(NavEntry.from)
      .where((e) => e.path.isNotEmpty)
      .toList();
  final groupOrder = <String>[];
  for (final e in visible) {
    if (!groupOrder.contains(e.group)) groupOrder.add(e.group);
  }
  return NavMenu([
    for (final g in groupOrder)
      NavGroup(
        g,
        visible.where((e) => e.group == g).toList()
          ..sort((a, b) => a.order.compareTo(b.order)),
      ),
  ], const []);
}

Future<NavMenu?> fetchNavMenu() async {
  final api = ScrollAPI();
  final base = api.objectServerUrl;
  if (base == null) return null;
  final res = await api.rawRequest(
    'POST',
    '${base}objects/action_nav_entries?format=json',
    data: const {},
  );
  final body = res['body'];
  if (res['status'] == 200 && body is Map && body['groups'] is List) {
    final menu = parseNavMenu(body);
    if (!menu.isEmpty) return menu;
  }
  final rows = await api.rawRequest(
    'GET',
    '${base}collections/nav_entries/records?limit=200',
  );
  final rb = rows['body'];
  if (rows['status'] == 200 && rb is Map && rb['records'] is List) {
    return navMenuFromRows((rb['records'] as List).whereType<Map>().toList());
  }
  return null;
}

// ---------------------------------------------------------------------------
// View records
// ---------------------------------------------------------------------------

const knownBlockKinds = {
  'list',
  'form',
  'detail',
  'related',
  'thread',
  'count',
  'aggregate',
  'markdown',
  'reader',
  'object',
};

class ViewBlock {
  final Map<String, dynamic> raw;
  const ViewBlock(this.raw);

  String get kind => '${raw['kind'] ?? ''}';
  bool get isKnown => knownBlockKinds.contains(kind);
  String? get collection {
    final c = raw['collection'];
    return c == null || '$c'.isEmpty ? null : '$c';
  }

  String? get title => raw['title']?.toString();
  dynamic operator [](String key) => raw[key];

  /// A block value, with "$record_id" resolved to the page's captured id
  /// (null when it can't resolve, like the web renderer).
  String? resolved(String key, String? recordId) {
    final v = raw[key];
    if (v == null) return null;
    if ('$v' == r'$record_id') return recordId;
    return '$v';
  }
}

class ServerView {
  final String id;
  final String title;
  final String route;
  final String layout;
  final bool pinned;
  final List<ViewBlock> blocks;

  /// Set when `blocks` isn't a JSON list (the page then shows one error card).
  final String? blocksError;

  const ServerView({
    required this.id,
    required this.title,
    required this.route,
    required this.layout,
    required this.pinned,
    required this.blocks,
    this.blocksError,
  });

  factory ServerView.from(Map raw) {
    List<ViewBlock> blocks = const [];
    String? error;
    final b = raw['blocks'];
    try {
      final decoded = b is String ? (b.trim().isEmpty ? [] : jsonDecode(b)) : b;
      if (decoded is List) {
        blocks = [
          for (final item in decoded)
            ViewBlock(item is Map ? Map<String, dynamic>.from(item) : {}),
        ];
      } else {
        error = 'blocks must be a JSON array';
      }
    } catch (_) {
      error = 'Invalid blocks JSON';
    }
    return ServerView(
      id: '${raw['id'] ?? ''}',
      title: '${raw['title'] ?? 'View'}',
      route: '${raw['route'] ?? ''}',
      layout: '${raw['layout'] ?? 'single'}',
      pinned: schemaBoolIsTrue(raw['pinned']),
      blocks: blocks,
      blocksError: error,
    );
  }

  /// A page with one generated list, for a collection that has no views
  /// record of its own (the web's convention-routed /{collection}).
  factory ServerView.listFor(String collection) => ServerView(
    id: '',
    title: _titleCase(collection),
    route: '/$collection',
    layout: 'single',
    pinned: false,
    blocks: [
      ViewBlock({
        'kind': 'list',
        'collection': collection,
        'search': true,
        'sort': true,
        'add': true,
      }),
    ],
  );

  /// One record's page when no views record covers it.
  factory ServerView.detailFor(String collection) => ServerView(
    id: '',
    title: singular(collection),
    route: '/$collection/{id}',
    layout: 'single',
    pinned: false,
    blocks: [
      ViewBlock({
        'kind': 'detail',
        'collection': collection,
        'record_id': r'$record_id',
      }),
    ],
  );
}

Future<List<ServerView>> fetchViews() async {
  final api = ScrollAPI();
  final base = api.objectServerUrl;
  if (base == null) return const [];
  final res = await api.rawRequest(
    'GET',
    '${base}collections/views/records?limit=500',
  );
  final body = res['body'];
  if (res['status'] != 200 || body is! Map) return const [];
  return [
    for (final r in (body['records'] as List? ?? const []).whereType<Map>())
      ServerView.from(r),
  ];
}

/// Match a view route against a path. Routes have at most one capture,
/// written `{name}` or `{name:type}`. Returns the captures (empty map for an
/// exact match) or null when the path doesn't match.
Map<String, String>? matchRoute(String pattern, String path) {
  String norm(String p) =>
      p.length > 1 && p.endsWith('/') ? p.substring(0, p.length - 1) : p;
  final a = norm(pattern).split('/');
  final b = norm(path).split('/');
  if (a.length != b.length) return null;
  final captures = <String, String>{};
  for (var i = 0; i < a.length; i++) {
    final seg = a[i];
    if (seg.startsWith('{') && seg.endsWith('}')) {
      if (b[i].isEmpty) return null;
      captures[seg.substring(1, seg.length - 1).split(':').first] = b[i];
    } else if (seg != b[i]) {
      return null;
    }
  }
  return captures;
}

class ViewMatch {
  final ServerView view;
  final String? recordId;
  const ViewMatch(this.view, this.recordId);
}

/// The view a path opens: an exact route first, then a one-capture route
/// (its capture becomes $record_id). Null when no view covers the path.
ViewMatch? findViewForPath(List<ServerView> views, String path) {
  for (final v in views) {
    if (v.route.isEmpty) continue;
    final m = matchRoute(v.route, path);
    if (m != null && m.isEmpty) return ViewMatch(v, null);
  }
  for (final v in views) {
    if (v.route.isEmpty) continue;
    final m = matchRoute(v.route, path);
    if (m != null && m.length == 1) return ViewMatch(v, m.values.first);
  }
  return null;
}

// ---------------------------------------------------------------------------
// Schema layout hints (schema root keys, snake_case)
// ---------------------------------------------------------------------------

class SchemaUi {
  final List<SchemaFieldSpec> fields;
  final String listMode;
  final List<String> listFields;
  final List<String> filterFields;
  final List<String> detailFields;
  final List<String> formFields;
  final String? flowField;
  final Map<String, dynamic> capabilities;
  final bool searchable;

  const SchemaUi({
    required this.fields,
    this.listMode = '',
    this.listFields = const [],
    this.filterFields = const [],
    this.detailFields = const [],
    this.formFields = const [],
    this.flowField,
    this.capabilities = const {},
    this.searchable = false,
  });

  static const empty = SchemaUi(fields: []);

  factory SchemaUi.from(Map<String, dynamic>? doc) {
    if (doc == null) return empty;
    final schema = doc['schema'] is Map
        ? Map<String, dynamic>.from(doc['schema'] as Map)
        : doc;
    final spec = SchemaFormSpec.fromSchema(schema);
    final views = schema['views'] is Map ? schema['views'] as Map : const {};
    List<String> strs(Object? v) =>
        v is List ? v.map((e) => '$e').toList() : const [];
    final forms = schema['forms'];
    final flow = schema['flow'];
    return SchemaUi(
      fields: spec.fields,
      listMode: '${views['list_mode'] ?? ''}',
      listFields: strs(views['list_fields']),
      filterFields: strs(views['filter_fields']),
      detailFields: strs(views['detail_fields']),
      formFields: forms is Map && forms['default'] is Map
          ? strs((forms['default'] as Map)['fields'])
          : const [],
      flowField: flow is Map && flow['field'] != null
          ? '${flow['field']}'
          : null,
      capabilities: schema['capabilities'] is Map
          ? Map<String, dynamic>.from(schema['capabilities'] as Map)
          : const {},
      searchable: schema['search'] is Map,
    );
  }

  SchemaFieldSpec? field(String name) {
    for (final f in fields) {
      if (f.name == name) return f;
    }
    return null;
  }

  /// Board grouping field, the web's defaultGroupField chain: flow.field,
  /// else the first enum with transitions, else the first enum.
  String? get boardField {
    if (flowField != null && field(flowField!) != null) return flowField;
    for (final f in fields) {
      if (f.isEnum && f.hasTransitions) return f.name;
    }
    for (final f in fields) {
      if (f.isEnum) return f.name;
    }
    return null;
  }

  /// Fields a detail page shows, in order: detail_fields if declared, else
  /// the form order, else schema order -- minus server-owned plumbing.
  List<String> get detailOrder {
    final base = detailFields.isNotEmpty
        ? detailFields
        : (formFields.isNotEmpty ? formFields : fields.map((f) => f.name));
    return base
        .where(
          (n) =>
              !const {'id', 'owner_id', 'created_at', 'updated_at'}.contains(n),
        )
        .toList();
  }
}

Future<Map<String, dynamic>?> fetchSchemaDoc(String collection) async {
  final api = ScrollAPI();
  final base = api.objectServerUrl;
  if (base == null) return null;
  final res = await api.rawRequest(
    'GET',
    '${base}api/schema/${Uri.encodeComponent(collection)}',
  );
  final body = res['body'];
  if (res['status'] == 200 && body is Map && body['schema'] is Map) {
    return Map<String, dynamic>.from(body['schema'] as Map);
  }
  return await api.getAdminSchema(collection) ??
      await api.getSchema(collection);
}

// ---------------------------------------------------------------------------
// Display rules shared with the web renderers
// ---------------------------------------------------------------------------

String _titleCase(String s) => s
    .replaceAll('-', ' ')
    .split('_')
    .where((p) => p.isNotEmpty)
    .map((p) => '${p[0].toUpperCase()}${p.substring(1)}')
    .join(' ');

String titleCaseName(String s) => _titleCase(s);

/// "tasks" → "Task", "categories" → "Category" (view_render.py's singular).
String singular(String collection) => collection
    .split('_')
    .map((w) {
      final one = w.endsWith('ies')
          ? '${w.substring(0, w.length - 3)}y'
          : (w.endsWith('s') ? w.substring(0, w.length - 1) : w);
      return one.isEmpty ? one : '${one[0].toUpperCase()}${one.substring(1)}';
    })
    .join(' ');

final _idish = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);
final _dateish = RegExp(r'^\d{4}-\d{2}-\d{2}');

/// What a row is called. Never the id (view_render.py's rowLabel): title /
/// name / label / subject, else the first human-shaped string.
String rowLabel(Map record, {String? titleField}) {
  if (titleField != null) {
    final v = record[titleField];
    return v == null || '$v'.isEmpty ? '(none)' : _clip('$v');
  }
  for (final k in const ['title', 'name', 'label', 'subject']) {
    final v = record[k];
    if (v != null && '$v'.trim().isNotEmpty) return _clip('$v');
  }
  for (final e in record.entries) {
    final key = '${e.key}';
    if (key == 'id' || key.endsWith('_id')) continue;
    final v = e.value;
    if (v is! String || v.trim().isEmpty) continue;
    final t = v.trim();
    if (_idish.hasMatch(t) || _dateish.hasMatch(t)) continue;
    return _clip(t.replaceAll(RegExp(r'\s+'), ' '));
  }
  return '(untitled)';
}

String _clip(String s) => s.length > 120 ? '${s.substring(0, 117)}…' : s;

/// "3h ago", "in 2d", "just now". Unparseable input comes back unchanged.
String relativeTime(String value, {DateTime? now}) {
  final t = DateTime.tryParse(value);
  if (t == null) return value;
  final d = (now ?? DateTime.now()).toUtc().difference(t.toUtc());
  final future = d.isNegative;
  final a = d.abs();
  String n;
  if (a.inSeconds < 45) return 'just now';
  if (a.inMinutes < 60) {
    n = '${a.inMinutes}m';
  } else if (a.inHours < 24) {
    n = '${a.inHours}h';
  } else if (a.inDays < 30) {
    n = '${a.inDays}d';
  } else if (a.inDays < 365) {
    n = '${a.inDays ~/ 30}mo';
  } else {
    n = '${a.inDays ~/ 365}y';
  }
  return future ? 'in $n' : '$n ago';
}

/// A value as the web renderers show it: `_cents` as dollars, booleans
/// Yes/No, datetimes relative, relations by their target's label.
String formatValue(
  String fieldName,
  SchemaFieldSpec? spec,
  dynamic value, {
  Map<String, String>? relationLabels,
  DateTime? now,
}) {
  if (value == null || '$value'.isEmpty) return '';
  if (fieldName.endsWith('_cents')) {
    final n = num.tryParse('$value');
    if (n != null) {
      final neg = n < 0;
      final s = (n.abs() / 100).toStringAsFixed(2);
      return '${neg ? '-' : ''}\$$s';
    }
  }
  if (spec != null && spec.isBoolean) {
    return schemaBoolIsTrue(value) ? 'Yes' : 'No';
  }
  if (spec != null && spec.isRelation) {
    return relationLabels?['$value'] ?? '$value';
  }
  if ((spec != null && spec.isDateTime) ||
      fieldName == 'created_at' ||
      fieldName == 'updated_at') {
    return relativeTime('$value', now: now);
  }
  return '$value';
}

/// Records of [collection] keyed by id → their display label, for showing
/// relation fields by name instead of raw ids. Cached per collection+field.
final Map<String, Future<Map<String, String>>> _labelCache = {};

Future<Map<String, String>> relationLabelsFor(
  String collection,
  String displayField,
) {
  final key = '${ScrollAPI().objectServerUrl}|$collection|$displayField';
  return _labelCache.putIfAbsent(key, () async {
    final api = ScrollAPI();
    final res = await api.rawRequest(
      'GET',
      '${api.objectServerUrl}collections/${Uri.encodeComponent(collection)}/records?limit=500',
    );
    final body = res['body'];
    if (res['status'] != 200 || body is! Map) return <String, String>{};
    return {
      for (final r in (body['records'] as List? ?? const []).whereType<Map>())
        if (r['id'] != null)
          '${r['id']}':
              (r[displayField] != null && '${r[displayField]}'.isNotEmpty)
              ? '${r[displayField]}'
              : rowLabel(r),
    };
  });
}

@visibleForTesting
void clearRelationLabelCache() => _labelCache.clear();

/// Forget cached labels for [collection] (after a write to it).
void invalidateRelationLabels(String collection) =>
    _labelCache.removeWhere((k, _) => k.contains('|$collection|'));
