// Native renderer for the object server's generative UI: draws a `views`
// record's blocks, and generated list/detail pages for collections without
// one, from the collection's schema -- the same contract the web renderers
// (app-views view_render.py, app-theme list.py) follow. Reads and writes go
// through the permission-enforced user routes, so the server decides what
// this credential may see and change.

import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'home_collections.dart';
import 'mockup.dart';
import 'realtime.dart';
import 'schema_form.dart';
import 'server_ui.dart';

// ---------------------------------------------------------------------------
// Navigation: a server path → the Scroll screen that shows it
// ---------------------------------------------------------------------------

class ServerViewsCache {
  static Future<List<ServerView>>? _pending;
  static String? _forUrl;

  static Future<List<ServerView>> load({bool refresh = false}) {
    final url = ScrollAPI().objectServerUrl;
    if (refresh || _pending == null || _forUrl != url) {
      _forUrl = url;
      _pending = fetchViews();
    }
    return _pending!;
  }
}

Future<bool> collectionReadable(String collection) async {
  final api = ScrollAPI();
  final res = await api.rawRequest(
    'GET',
    '${api.objectServerUrl}collections/${Uri.encodeComponent(collection)}/records?limit=1',
  );
  return res['status'] == 200;
}

class ServerUiNav {
  final NavigateFn? navigate;

  /// Paths Scroll answers with its own screen (e.g. /shell → AI Chat).
  final Widget? Function(String path)? native;
  const ServerUiNav({this.navigate, this.native});

  /// Open a server path: a native screen, else the `views` record whose
  /// route matches, else the convention route /{collection}[/{id}], else a
  /// "planned" page (the web has it; Scroll doesn't yet).
  Future<void> open(BuildContext context, String path, {String? title}) async {
    final go = navigate;
    if (go == null) return;
    final nativeScreen = native?.call(path);
    if (nativeScreen != null) {
      go(title ?? path, nativeScreen, Icons.apps);
      return;
    }
    final views = await ServerViewsCache.load();
    final match = findViewForPath(views, path);
    if (match != null) {
      go(
        match.view.title,
        ServerViewPage(view: match.view, recordId: match.recordId, nav: this),
        Icons.web_asset_outlined,
      );
      return;
    }
    final segs = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segs.isNotEmpty &&
        segs.length <= 2 &&
        await collectionReadable(segs[0])) {
      final c = segs[0];
      if (segs.length == 1) {
        go(
          title ?? titleCaseName(c),
          ServerViewPage(view: ServerView.listFor(c), nav: this),
          Icons.table_rows_outlined,
        );
      } else {
        go(
          singular(c),
          ServerViewPage(
            view: ServerView.detailFor(c),
            recordId: segs[1],
            nav: this,
          ),
          Icons.article_outlined,
        );
      }
      return;
    }
    go(title ?? path, PlannedPage(title: title ?? path, path: path), Icons.web);
  }
}

/// A server page Scroll doesn't render yet: pink "planned", with the URL.
class PlannedPage extends StatelessWidget {
  final String title;
  final String path;
  const PlannedPage({super.key, required this.title, required this.path});

  @override
  Widget build(BuildContext context) {
    final base = ScrollAPI().objectServerUrl ?? '';
    final url = base.endsWith('/') && path.startsWith('/')
        ? '$base${path.substring(1)}'
        : '$base$path';
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(24),
        child: MockupOutline(
          tag: 'PLANNED',
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text(
                  'This app runs on the server\'s web interface. Scroll '
                  'doesn\'t show it yet.',
                  style: TextStyle(color: kMockupColor),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  url,
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// A view page
// ---------------------------------------------------------------------------

class ServerViewPage extends StatelessWidget {
  final ServerView view;
  final String? recordId;
  final ServerUiNav nav;
  const ServerViewPage({
    super.key,
    required this.view,
    this.recordId,
    required this.nav,
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      for (final (i, b) in view.blocks.indexed)
        KeyedSubtree(
          key: ValueKey('${view.id}|$i|$recordId'),
          child: buildViewBlock(b, recordId: recordId, nav: nav),
        ),
    ];
    Widget body;
    if (view.blocksError != null) {
      body = ErrorCard(view.blocksError!);
    } else if (children.isEmpty) {
      body = const Text(
        'This view has no blocks yet.',
        style: TextStyle(color: Colors.white54),
      );
    } else {
      body = LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          if (view.layout == 'grid') {
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final child in children)
                  SizedBox(width: w >= 820 ? (w - 32) / 3 : w, child: child),
              ],
            );
          }
          if (view.layout == 'two_column' && w >= 900) {
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final child in children)
                  SizedBox(width: (w - 16) / 2, child: child),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final child in children) ...[
                child,
                const SizedBox(height: 16),
              ],
            ],
          );
        },
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                view.title,
                style: Theme.of(context).textTheme.headlineSmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (view.route.isNotEmpty)
              Text(
                view.id.isEmpty ? 'generated from the schema' : view.route,
                style: const TextStyle(fontSize: 11, color: Colors.white30),
              ),
          ],
        ),
        const SizedBox(height: 16),
        body,
      ],
    );
  }
}

Widget buildViewBlock(
  ViewBlock b, {
  String? recordId,
  required ServerUiNav nav,
}) {
  if (!b.isKnown) {
    return ErrorCard(
      b.kind.isEmpty
          ? 'Unsupported block'
          : 'Unsupported block kind: ${b.kind}',
    );
  }
  final c = b.collection;
  switch (b.kind) {
    case 'list':
      if (c == null) return const ErrorCard('list block needs a collection');
      return ListBlockView(block: b, recordId: recordId, nav: nav);
    case 'related':
      final fk = b['fk_field']?.toString();
      if (c == null || fk == null) {
        return const ErrorCard('related block needs a collection and fk_field');
      }
      final match = b.resolved('match', recordId);
      if (match == null) {
        return const ErrorCard("related block's match did not resolve");
      }
      return ListBlockView(
        block: b,
        recordId: recordId,
        nav: nav,
        where: {fk: match},
        fixed: {fk: match},
        isRelated: true,
      );
    case 'detail':
      if (c == null) return const ErrorCard('detail block needs a collection');
      final id = b.resolved('record_id', recordId);
      if (id == null) return const ErrorCard('detail block needs a record_id');
      return DetailBlockView(block: b, recordId: id, nav: nav);
    case 'count':
      if (c == null) return const ErrorCard('count block needs a collection');
      return CountBlockView(block: b, recordId: recordId);
    case 'aggregate':
      if (c == null)
        return const ErrorCard('aggregate block needs a collection');
      return CountBlockView(block: b, recordId: recordId, aggregate: true);
    case 'markdown':
      return MarkdownBlockView(text: '${b['text'] ?? ''}');
    case 'form':
      if (c == null) return const ErrorCard('form block needs a collection');
      return FormBlockView(block: b, recordId: recordId);
    case 'thread':
      if (c == null) return const ErrorCard('thread block needs a collection');
      final id = b.resolved('record_id', recordId);
      if (id == null) return const ErrorCard('thread block needs a record_id');
      return ThreadBlockView(parentCollection: c, parentId: id);
    case 'reader':
      final url = b['url']?.toString();
      if (url == null || url.isEmpty) {
        return const ErrorCard('reader block needs a url');
      }
      return ReaderBlockView(url: url);
    case 'object':
      return PlannedCard(
        title: b.title ?? 'Custom panel',
        note:
            'A hand-written object (${b['object_id'] ?? '?'}) the web page '
            'shows inline. Scroll doesn\'t run object panels yet.',
      );
  }
  return const ErrorCard('Invalid block');
}

// ---------------------------------------------------------------------------
// Small shared pieces
// ---------------------------------------------------------------------------

class ErrorCard extends StatelessWidget {
  final String message;
  const ErrorCard(this.message, {super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.orange.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
    ),
    child: Text(
      message,
      style: const TextStyle(color: Colors.orangeAccent, fontSize: 13),
    ),
  );
}

/// Pink: the server has this, Scroll doesn't show it yet.
class PlannedCard extends StatelessWidget {
  final String title;
  final String note;
  const PlannedCard({super.key, required this.title, required this.note});

  @override
  Widget build(BuildContext context) => MockupOutline(
    tag: 'PLANNED',
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(note, style: const TextStyle(fontSize: 12, color: kMockupColor)),
        ],
      ),
    ),
  );
}

class _Panel extends StatelessWidget {
  final Widget child;
  const _Panel({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.white10),
    ),
    child: child,
  );
}

MaterialColor _badgeColor(String value) {
  const palette = <MaterialColor>[
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.red,
    Colors.indigo,
    Colors.brown,
  ];
  return palette[value.hashCode.abs() % palette.length];
}

class EnumBadge extends StatelessWidget {
  final String value;
  const EnumBadge(this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = _badgeColor(value);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(value, style: TextStyle(fontSize: 11, color: c.shade200)),
    );
  }
}

Future<Map<String, dynamic>> _getJson(String path) async {
  final api = ScrollAPI();
  return api.rawRequest('GET', '${api.objectServerUrl}$path');
}

String _q(Map<String, String> params) => params.entries
    .map(
      (e) =>
          '&${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
    )
    .join();

String _failure(Map<String, dynamic> res) {
  final body = res['body'];
  final detail = body is Map && body['error'] != null
      ? ': ${body['error']}'
      : '';
  return '${httpFailure(res['status'], res['error'])}$detail';
}

void _toast(BuildContext context, String text) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

/// Relation labels for the given fields of a schema.
Future<Map<String, Map<String, String>>> _labelsFor(
  SchemaUi schema,
  Iterable<String> fieldNames,
) async {
  final out = <String, Map<String, String>>{};
  for (final name in fieldNames) {
    final f = schema.field(name);
    if (f == null || !f.isRelation) continue;
    out[name] = await relationLabelsFor(
      f.relationCollection!,
      f.relationDisplayField,
    );
  }
  return out;
}

// ---------------------------------------------------------------------------
// list / related
// ---------------------------------------------------------------------------

class ListBlockView extends StatefulWidget {
  final ViewBlock block;
  final String? recordId;
  final ServerUiNav nav;

  /// Server-side scope (field=value): a block's `where`, or a related
  /// block's foreign key.
  final Map<String, String> where;

  /// Values a new record gets without asking (a related child's parent id).
  final Map<String, String> fixed;
  final bool isRelated;

  const ListBlockView({
    super.key,
    required this.block,
    required this.recordId,
    required this.nav,
    this.where = const {},
    this.fixed = const {},
    this.isRelated = false,
  });

  @override
  State<ListBlockView> createState() => _ListBlockViewState();
}

class _ListBlockViewState extends State<ListBlockView> {
  SchemaUi _schema = SchemaUi.empty;
  bool _schemaLoaded = false;
  List<Map<String, dynamic>> _rows = const [];
  Map<String, Map<String, String>> _labels = const {};
  bool _loading = true;
  String? _error;
  final _search = TextEditingController();
  late bool _oldest;
  final Map<String, String> _picks = {};
  bool _showAll = false;
  bool _boardAsTable = false;
  VoidCallback? _unbind;
  Timer? _debounce;

  ViewBlock get b => widget.block;
  String get collection => b.collection!;

  @override
  void initState() {
    super.initState();
    _oldest = b['sort'] == 'oldest' || b['sort'] == 'asc';
    _load();
    _unbind = ScrollRealtime().bind(collection, () {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 200), _load);
    });
  }

  @override
  void dispose() {
    _unbind?.call();
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Map<String, String> get _blockWhere {
    final w = b['where'];
    return w is Map
        ? {for (final e in w.entries) '${e.key}': '${e.value}'}
        : {};
  }

  Future<void> _load() async {
    if (!_schemaLoaded) {
      _schema = SchemaUi.from(await fetchSchemaDoc(collection));
      _schemaLoaded = true;
    }
    final params = {..._blockWhere, ...widget.where, ..._picks};
    final res = await _getJson(
      'collections/${Uri.encodeComponent(collection)}/records?limit=500${_q(params)}',
    );
    if (!mounted) return;
    final body = res['body'];
    if (res['status'] != 200 || body is! Map) {
      setState(() {
        _loading = false;
        _error = 'Could not load $collection (${_failure(res)})';
      });
      return;
    }
    final rows = [
      for (final r in (body['records'] as List? ?? const []).whereType<Map>())
        Map<String, dynamic>.from(r),
    ];
    final labels = await _labelsFor(_schema, _shownFields());
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _labels = labels;
      _loading = false;
      _error = null;
    });
  }

  bool get _plainRows {
    final f = b['filters'];
    return (f is Map && f.isNotEmpty) || b['limit'] != null;
  }

  String get _mode {
    if (_plainRows) return 'rows';
    final m = _schema.listMode;
    if (m == 'board') {
      if (_schema.boardField == null) return 'rows';
      return _boardAsTable ? 'table' : 'board';
    }
    if (m == 'table') return 'table';
    if (m == 'tree' || m == 'calendar') return 'rows';
    return 'rows';
  }

  String? get _modeNotice {
    if (_plainRows) return null;
    final m = _schema.listMode;
    if (m == 'board' && _schema.boardField == null) {
      return 'board mode needs an enum field -- none found; showing rows';
    }
    if (m == 'tree' || m == 'calendar') {
      return '${m[0].toUpperCase()}${m.substring(1)} mode isn\'t built in Scroll yet; showing rows.';
    }
    return null;
  }

  String? get _titleField => b['title_field']?.toString();

  List<String> _shownFields() {
    if (_schema.listFields.isNotEmpty) return _schema.listFields;
    final names = _schema.fields
        .map((f) => f.name)
        .where((n) => !serverOwnedFields.contains(n))
        .toList();
    return names.take(5).toList();
  }

  List<Map<String, dynamic>> _visible() {
    var list = _rows;
    final f = b['filters'];
    if (f is Map && f.isNotEmpty) {
      list = list
          .where(
            (r) => f.entries.every((e) => '${r[e.key] ?? ''}' == '${e.value}'),
          )
          .toList();
    }
    final q = _search.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where(
            (r) =>
                r.values.any((v) => v is String && v.toLowerCase().contains(q)),
          )
          .toList();
    }
    final sortBy = b['sort_by']?.toString();
    if (sortBy != null) {
      final desc = b['sort_dir'] != 'asc';
      list = [...list]
        ..sort((x, y) {
          final a = x[sortBy], c = y[sortBy];
          final na = num.tryParse('$a'), nc = num.tryParse('$c');
          final r = na != null && nc != null
              ? na.compareTo(nc)
              : '${a ?? ''}'.compareTo('${c ?? ''}');
          return desc ? -r : r;
        });
    } else {
      list = [...list]
        ..sort((x, y) {
          final r = '${x['created_at'] ?? ''}'.compareTo(
            '${y['created_at'] ?? ''}',
          );
          return _oldest ? r : -r;
        });
    }
    final limit = b['limit'];
    if (limit != null) list = list.take(int.tryParse('$limit') ?? 0).toList();
    return list;
  }

  bool get _linkable => b['row_actions'] != false && b['link'] != false;

  void _openRow(Map<String, dynamic> r) {
    if (!_linkable) return;
    final tpl = b['href_template']?.toString();
    if (tpl != null) {
      final path = tpl.replaceAllMapped(
        RegExp(r'\{(\w+)\}'),
        (m) => Uri.encodeComponent('${r[m[1]] ?? ''}'),
      );
      widget.nav.open(context, path);
      return;
    }
    if (b['href_field'] != null) return; // an external link, not a page
    final id = r['id'];
    if (id == null) return;
    widget.nav.open(context, '/$collection/${Uri.encodeComponent('$id')}');
  }

  Future<void> _add() async {
    final id = await createServerRecord(
      context,
      collection,
      fixed: widget.fixed,
    );
    if (id != null) {
      invalidateRelationLabels(collection);
      await _load();
    }
  }

  Future<void> _move(Map<String, dynamic> r, String field, String to) async {
    final res = await ScrollAPI().putUserCollectionRecord(
      collection,
      '${r['id']}',
      {field: to},
    );
    if (!mounted) return;
    final ok = res['status'] is int && (res['status'] as int) < 300;
    _toast(context, ok ? 'Moved to $to' : 'Move refused (${_failure(res)})');
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final heading = b.title;
    final toolbar = <Widget>[
      if (b['search'] == true)
        SizedBox(
          width: 260,
          height: 38,
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Search…',
              prefixIcon: Icon(Icons.search, size: 18),
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
      if (b['sort'] == true || b['sort'] == 'oldest' || b['sort'] == 'asc')
        DropdownButton<bool>(
          value: _oldest,
          underline: const SizedBox(),
          items: const [
            DropdownMenuItem(value: false, child: Text('Newest')),
            DropdownMenuItem(value: true, child: Text('Oldest')),
          ],
          onChanged: (v) => setState(() => _oldest = v ?? false),
        ),
      for (final name in _schema.filterFields) _filterControl(name),
      if (!_plainRows &&
          _schema.listMode == 'board' &&
          _schema.boardField != null &&
          _schema.listFields.isNotEmpty)
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Board')),
            ButtonSegment(value: true, label: Text('Table')),
          ],
          selected: {_boardAsTable},
          onSelectionChanged: (s) => setState(() => _boardAsTable = s.first),
        ),
      if (b['add'] == true || widget.isRelated)
        FilledButton.icon(
          onPressed: _add,
          icon: const Icon(Icons.add, size: 16),
          label: Text(
            b['add_label']?.toString().replaceFirst(RegExp(r'^\+\s*'), '') ??
                (widget.isRelated
                    ? 'Add ${singular(collection)}'
                    : 'New ${singular(collection)}'),
          ),
        ),
      IconButton(
        tooltip: 'Reload',
        icon: const Icon(Icons.refresh, size: 18),
        onPressed: _load,
      ),
    ];

    Widget content;
    if (_loading) {
      content = const Padding(
        padding: EdgeInsets.all(16),
        child: LinearProgressIndicator(minHeight: 2),
      );
    } else if (_error != null) {
      content = ErrorCard(_error!);
    } else {
      final all = _visible();
      final cap = int.tryParse('${b['row_limit'] ?? ''}') ?? 50;
      final shown = _showAll ? all : all.take(cap).toList();
      if (all.isEmpty) {
        content = const Padding(
          padding: EdgeInsets.all(12),
          child: Text('Nothing yet.', style: TextStyle(color: Colors.white54)),
        );
      } else {
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            switch (_mode) {
              'board' => _board(all),
              'table' => _table(shown),
              _ => _rowsView(shown),
            },
            if (_mode != 'board' && all.length > cap)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _showAll = !_showAll),
                  child: Text(
                    _showAll ? 'Show first $cap' : 'Show all ${all.length}',
                  ),
                ),
              ),
          ],
        );
      }
    }

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (heading != null) ...[
            Text(heading, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
          ],
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: toolbar,
          ),
          if (_modeNotice != null) ...[
            const SizedBox(height: 8),
            Text(
              _modeNotice!,
              style: const TextStyle(fontSize: 12, color: kMockupColor),
            ),
          ],
          const SizedBox(height: 10),
          content,
        ],
      ),
    );
  }

  Widget _filterControl(String name) {
    final f = _schema.field(name);
    if (f == null) return const SizedBox.shrink();
    final options = f.isBoolean ? const ['true', 'false'] : f.enumValues;
    if (options.isEmpty) return const SizedBox.shrink();
    return DropdownButton<String>(
      value: _picks[name] ?? '',
      underline: const SizedBox(),
      items: [
        DropdownMenuItem(
          value: '',
          child: Text('All ${f.label.toLowerCase()}'),
        ),
        for (final o in options)
          DropdownMenuItem(
            value: o,
            child: Text(f.isBoolean ? (o == 'true' ? 'Yes' : 'No') : o),
          ),
      ],
      onChanged: (v) {
        setState(() {
          if (v == null || v.isEmpty) {
            _picks.remove(name);
          } else {
            _picks[name] = v;
          }
          _loading = true;
        });
        _load(); // server-side field=value, after the permission row filter
      },
    );
  }

  String _cell(Map<String, dynamic> r, String name) => formatValue(
    name,
    _schema.field(name),
    r[name],
    relationLabels: _labels[name],
  );

  Widget _rowsView(List<Map<String, dynamic>> rows) {
    final tf = _titleField;
    final sub = b['subtitle_field']?.toString();
    final subLabel = b['subtitle_label']?.toString();
    final extra = _shownFields().where((n) => n != tf).take(3).toList();
    return Column(
      children: [
        for (final r in rows)
          InkWell(
            onTap: _linkable ? () => _openRow(r) : null,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: Colors.white10,
                    child: Text(
                      rowLabel(
                        r,
                        titleField: tf,
                      ).characters.first.toUpperCase(),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rowLabel(r, titleField: tf),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Builder(
                          builder: (_) {
                            final text = sub != null
                                ? (r[sub] == null
                                      ? ''
                                      : '${subLabel != null ? '$subLabel: ' : ''}${_cell(r, sub)}')
                                : extra
                                      .where(
                                        (n) =>
                                            !(_schema.field(n)?.isEnum ??
                                                false),
                                      )
                                      .map((n) => _cell(r, n))
                                      .where(
                                        (v) =>
                                            v.isNotEmpty &&
                                            v != rowLabel(r, titleField: tf),
                                      )
                                      .join(' · ');
                            return text.isEmpty
                                ? const SizedBox.shrink()
                                : Text(
                                    text,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white38,
                                    ),
                                  );
                          },
                        ),
                      ],
                    ),
                  ),
                  for (final n in extra.where(
                    (n) => _schema.field(n)?.isEnum ?? false,
                  ))
                    if ('${r[n] ?? ''}'.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: EnumBadge('${r[n]}'),
                      ),
                  const SizedBox(width: 10),
                  Text(
                    formatValue('created_at', null, r['created_at']),
                    style: const TextStyle(fontSize: 11, color: Colors.white30),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _table(List<Map<String, dynamic>> rows) {
    final cols = _shownFields();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        showCheckboxColumn: false,
        headingRowHeight: 36,
        dataRowMinHeight: 32,
        dataRowMaxHeight: 40,
        columns: [
          for (final c in cols)
            DataColumn(label: Text(_schema.field(c)?.label ?? c)),
        ],
        rows: [
          for (final r in rows)
            DataRow(
              onSelectChanged: _linkable ? (_) => _openRow(r) : null,
              cells: [
                for (final c in cols)
                  DataCell(
                    (_schema.field(c)?.isEnum ?? false) &&
                            '${r[c] ?? ''}'.isNotEmpty
                        ? EnumBadge('${r[c]}')
                        : ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 320),
                            child: Text(
                              _cell(r, c),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _board(List<Map<String, dynamic>> rows) {
    final field = _schema.boardField!;
    final spec = _schema.field(field)!;
    final columns = ['', ...spec.enumValues];
    final tf = _titleField;
    final cardFields = _schema.listFields
        .where((n) => n != field && n != tf && n != 'title')
        .take(3)
        .toList();
    bool allowed(String from, String to) =>
        from != to &&
        (from.isEmpty || spec.allowedEnumValues(from).contains(to));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final col in columns)
            DragTarget<Map<String, dynamic>>(
              onWillAcceptWithDetails: (d) =>
                  col.isNotEmpty && allowed('${d.data[field] ?? ''}', col),
              onAcceptWithDetails: (d) => _move(d.data, field, col),
              builder: (context, candidate, _) {
                final cards = rows
                    .where((r) => '${r[field] ?? ''}' == col)
                    .toList();
                if (col.isEmpty && cards.isEmpty)
                  return const SizedBox.shrink();
                return Container(
                  width: 250,
                  margin: const EdgeInsets.only(right: 10),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: candidate.isNotEmpty
                        ? Colors.blue.withValues(alpha: 0.08)
                        : Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          col.isEmpty
                              ? const Text(
                                  '(unset)',
                                  style: TextStyle(color: Colors.white54),
                                )
                              : EnumBadge(col),
                          const Spacer(),
                          Text(
                            '${cards.length}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white38,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (final r in cards)
                        Draggable<Map<String, dynamic>>(
                          data: r,
                          feedback: Material(
                            color: Colors.transparent,
                            child: SizedBox(
                              width: 234,
                              child: _boardCard(
                                r,
                                tf,
                                cardFields,
                                field,
                                spec,
                                allowed,
                              ),
                            ),
                          ),
                          childWhenDragging: Opacity(
                            opacity: 0.3,
                            child: _boardCard(
                              r,
                              tf,
                              cardFields,
                              field,
                              spec,
                              allowed,
                            ),
                          ),
                          child: _boardCard(
                            r,
                            tf,
                            cardFields,
                            field,
                            spec,
                            allowed,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _boardCard(
    Map<String, dynamic> r,
    String? tf,
    List<String> cardFields,
    String field,
    SchemaFieldSpec spec,
    bool Function(String, String) allowed,
  ) {
    final current = '${r[field] ?? ''}';
    final moves = spec.enumValues.where((v) => allowed(current, v)).toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: InkWell(
        onTap: _linkable ? () => _openRow(r) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rowLabel(r, titleField: tf),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    for (final n in cardFields)
                      if (_cell(r, n).isNotEmpty)
                        Text(
                          '${_schema.field(n)?.label ?? n}: ${_cell(r, n)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white38,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                  ],
                ),
              ),
              if (moves.isNotEmpty)
                PopupMenuButton<String>(
                  tooltip: 'Move to…',
                  icon: const Icon(Icons.more_vert, size: 16),
                  itemBuilder: (_) => [
                    for (final m in moves)
                      PopupMenuItem(value: m, child: Text('Move to $m')),
                  ],
                  onSelected: (to) => _move(r, field, to),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// detail
// ---------------------------------------------------------------------------

class DetailBlockView extends StatefulWidget {
  final ViewBlock block;
  final String recordId;
  final ServerUiNav nav;
  const DetailBlockView({
    super.key,
    required this.block,
    required this.recordId,
    required this.nav,
  });

  @override
  State<DetailBlockView> createState() => _DetailBlockViewState();
}

class _DetailBlockViewState extends State<DetailBlockView> {
  SchemaUi _schema = SchemaUi.empty;
  Map<String, dynamic>? _record;
  Map<String, Map<String, String>> _labels = const {};
  String? _error;
  bool _deleted = false;
  VoidCallback? _unbind;

  String get collection => widget.block.collection!;

  @override
  void initState() {
    super.initState();
    _load();
    _unbind = ScrollRealtime().bind(collection, _load);
  }

  @override
  void dispose() {
    _unbind?.call();
    super.dispose();
  }

  Future<void> _load() async {
    if (_schema.fields.isEmpty) {
      _schema = SchemaUi.from(await fetchSchemaDoc(collection));
    }
    final res = await _getJson(
      'collections/${Uri.encodeComponent(collection)}/records/${Uri.encodeComponent(widget.recordId)}',
    );
    if (!mounted) return;
    final body = res['body'];
    if (res['status'] != 200 || body is! Map) {
      setState(() {
        _error = res['status'] == 404
            ? 'This ${singular(collection).toLowerCase()} does not exist or is not shared with you.'
            : 'Could not load it (${_failure(res)})';
      });
      return;
    }
    final record = Map<String, dynamic>.from(
      body['record'] is Map ? body['record'] as Map : body,
    );
    final labels = await _labelsFor(_schema, _schema.detailOrder);
    if (!mounted) return;
    setState(() {
      _record = record;
      _labels = labels;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_deleted) {
      return const _Panel(
        child: Text('Deleted.', style: TextStyle(color: Colors.white54)),
      );
    }
    if (_error != null) return ErrorCard(_error!);
    final r = _record;
    if (r == null) {
      return const _Panel(child: LinearProgressIndicator(minHeight: 2));
    }
    final b = widget.block;
    final order = _schema.detailOrder.isNotEmpty
        ? _schema.detailOrder
        : r.keys.where((k) => !serverOwnedFields.contains(k)).toList();
    final caps = [
      if (_schema.capabilities['comments'] == true) 'Comments',
      if (_schema.capabilities['attachments'] == true) 'Attachments',
      if (_schema.capabilities['shareable'] == true) 'Sharing',
    ];
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  rowLabel(r),
                  style: Theme.of(context).textTheme.titleLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (b['editable'] != false)
                OutlinedButton.icon(
                  onPressed: () async {
                    if (await editServerRecord(context, collection, r)) {
                      invalidateRelationLabels(collection);
                      await _load();
                    }
                  },
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Edit'),
                ),
              if (b['deletable'] != false) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: () async {
                    if (await deleteServerRecord(
                      context,
                      collection,
                      '${r['id']}',
                    )) {
                      invalidateRelationLabels(collection);
                      if (mounted) setState(() => _deleted = true);
                    }
                  },
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Delete'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          for (final name in order)
            if (r.containsKey(name)) _field(name, r[name]),
          const SizedBox(height: 8),
          Text(
            [
              if (r['created_at'] != null)
                'created ${formatValue('created_at', null, r['created_at'])}',
              if (r['updated_at'] != null)
                'updated ${formatValue('updated_at', null, r['updated_at'])}',
            ].join(' · '),
            style: const TextStyle(fontSize: 11, color: Colors.white30),
          ),
          if (caps.isNotEmpty) ...[
            const SizedBox(height: 12),
            PlannedCard(
              title: caps.join(' · '),
              note:
                  'This ${singular(collection).toLowerCase()} has ${caps.join(', ').toLowerCase()} '
                  'on the web. Scroll doesn\'t show them yet.',
            ),
          ],
        ],
      ),
    );
  }

  Widget _field(String name, dynamic value) {
    final spec = _schema.field(name);
    final label = spec?.label ?? titleCaseName(name);
    Widget shown;
    if (value == null || '$value'.isEmpty) {
      shown = const Text('—', style: TextStyle(color: Colors.white24));
    } else if (spec != null && spec.isEnum) {
      shown = Align(
        alignment: Alignment.centerLeft,
        child: EnumBadge('$value'),
      );
    } else if (spec != null && spec.isRelation) {
      final text = formatValue(
        name,
        spec,
        value,
        relationLabels: _labels[name],
      );
      shown = InkWell(
        onTap: () => widget.nav.open(
          context,
          '/${spec.relationCollection}/${Uri.encodeComponent('$value')}',
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.lightBlueAccent,
            decoration: TextDecoration.underline,
          ),
        ),
      );
    } else {
      shown = SelectableText(formatValue(name, spec, value));
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ),
          Expanded(child: shown),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// count / aggregate
// ---------------------------------------------------------------------------

class CountBlockView extends StatefulWidget {
  final ViewBlock block;
  final String? recordId;
  final bool aggregate;
  const CountBlockView({
    super.key,
    required this.block,
    required this.recordId,
    this.aggregate = false,
  });

  @override
  State<CountBlockView> createState() => _CountBlockViewState();
}

class _CountBlockViewState extends State<CountBlockView> {
  List<Map>? _rows;
  String? _error;
  VoidCallback? _unbind;

  @override
  void initState() {
    super.initState();
    _load();
    _unbind = ScrollRealtime().bind(widget.block.collection!, _load);
  }

  @override
  void dispose() {
    _unbind?.call();
    super.dispose();
  }

  Future<void> _load() async {
    final res = await _getJson(
      'collections/${Uri.encodeComponent(widget.block.collection!)}/records?limit=500',
    );
    if (!mounted) return;
    final body = res['body'];
    setState(() {
      if (res['status'] != 200 || body is! Map) {
        _error = 'could not load ${widget.block.collection}';
      } else {
        _rows = (body['records'] as List? ?? const [])
            .whereType<Map>()
            .toList();
        _error = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ErrorCard(_error!);
    final rows = _rows;
    if (rows == null)
      return const _Panel(child: LinearProgressIndicator(minHeight: 2));
    final b = widget.block;
    var list = rows;
    final fk = b['fk_field']?.toString();
    final match = b.resolved('match', widget.recordId);
    final filters = b['filters'];
    if (widget.aggregate && fk != null && match != null) {
      list = list.where((r) => '${r[fk]}' == match).toList();
    } else if (filters is Map) {
      list = list
          .where(
            (r) => filters.entries.every(
              (e) => '${r[e.key] ?? ''}' == '${e.value}',
            ),
          )
          .toList();
    }
    if (!widget.aggregate) {
      final n = list.length;
      final warn =
          b['warn_over'] != null &&
          n > (num.tryParse('${b['warn_over']}') ?? n);
      return _stat('$n', b['label']?.toString() ?? b.collection!, danger: warn);
    }
    final sums = (b['sums'] is List ? b['sums'] as List : const [])
        .whereType<String>()
        .toList();
    final totals = {
      for (final f in sums)
        f: list.fold<num>(0, (a, r) => a + (num.tryParse('${r[f]}') ?? 0)),
    };
    String value(String f) => f.endsWith('_cents')
        ? (totals[f]! / 100).toStringAsFixed(2)
        : '${totals[f]}';
    String label(String f) =>
        titleCaseName(f.replaceFirst(RegExp(r'_cents$'), ''));
    final balance = b['balance'];
    final cards = <Widget>[
      for (final f in sums) _stat(value(f), label(f)),
      if (balance is List && balance.length == 2)
        totals['${balance[0]}'] == totals['${balance[1]}']
            ? _stat('✓', 'Balanced')
            : _stat('✗', 'Not balanced', danger: true),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (b.title != null) ...[
          Text(b.title!, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
        ],
        cards.isEmpty
            ? const Text(
                'Nothing to total.',
                style: TextStyle(color: Colors.white54),
              )
            : Wrap(spacing: 12, runSpacing: 12, children: cards),
      ],
    );
  }

  Widget _stat(String n, String label, {bool danger = false}) => Container(
    width: 180,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: (danger ? Colors.red : Colors.blue).withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: (danger ? Colors.red : Colors.blue).withValues(alpha: 0.3),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          n,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: danger ? Colors.red[300] : null,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.white54),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// markdown (the web's safe subset: paragraphs, **bold**, *italic*, links)
// ---------------------------------------------------------------------------

class MarkdownBlockView extends StatelessWidget {
  final String text;
  const MarkdownBlockView({super.key, required this.text});

  static List<InlineSpan> inline(String s) {
    final spans = <InlineSpan>[];
    final re = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*|\[([^\]]+)\]\(([^)]+)\)');
    var at = 0;
    for (final m in re.allMatches(s)) {
      if (m.start > at) spans.add(TextSpan(text: s.substring(at, m.start)));
      if (m[1] != null) {
        spans.add(
          TextSpan(
            text: m[1],
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        );
      } else if (m[2] != null) {
        spans.add(
          TextSpan(
            text: m[2],
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: m[3],
            style: const TextStyle(
              color: Colors.lightBlueAccent,
              decoration: TextDecoration.underline,
            ),
          ),
        );
      }
      at = m.end;
    }
    if (at < s.length) spans.add(TextSpan(text: s.substring(at)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final paras = text
        .split(RegExp(r'\n\s*\n'))
        .where((p) => p.trim().isNotEmpty);
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final p in paras)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SelectableText.rich(TextSpan(children: inline(p.trim()))),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// form / thread / reader
// ---------------------------------------------------------------------------

class FormBlockView extends StatelessWidget {
  final ViewBlock block;
  final String? recordId;
  const FormBlockView({super.key, required this.block, required this.recordId});

  @override
  Widget build(BuildContext context) {
    final c = block.collection!;
    final fixedRaw = block['fixed'];
    final fixed = <String, dynamic>{
      if (fixedRaw is Map)
        for (final e in fixedRaw.entries)
          if (('${e.value}' == r'$record_id' ? recordId : '${e.value}') != null)
            '${e.key}': '${e.value}' == r'$record_id' ? recordId : '${e.value}',
    };
    final editId = block.resolved('record_id', recordId);
    return _Panel(
      child: Row(
        children: [
          Expanded(
            child: Text(
              block.title ??
                  (editId != null
                      ? 'Edit ${singular(c)}'
                      : 'New ${singular(c)}'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          FilledButton.icon(
            onPressed: () async {
              if (editId == null) {
                await createServerRecord(context, c, fixed: fixed);
                return;
              }
              final res = await _getJson(
                'collections/${Uri.encodeComponent(c)}/records/${Uri.encodeComponent(editId)}',
              );
              final body = res['body'];
              if (!context.mounted || body is! Map) return;
              final rec = Map<String, dynamic>.from(
                body['record'] is Map ? body['record'] as Map : body,
              );
              await editServerRecord(context, c, rec);
            },
            icon: Icon(editId == null ? Icons.add : Icons.edit, size: 16),
            label: Text(editId == null ? 'New ${singular(c)}' : 'Edit'),
          ),
        ],
      ),
    );
  }
}

class ThreadBlockView extends StatefulWidget {
  final String parentCollection;
  final String parentId;
  const ThreadBlockView({
    super.key,
    required this.parentCollection,
    required this.parentId,
  });

  @override
  State<ThreadBlockView> createState() => _ThreadBlockViewState();
}

class _ThreadBlockViewState extends State<ThreadBlockView> {
  List<Map>? _comments;
  String? _error;
  final _text = TextEditingController();
  VoidCallback? _unbind;

  @override
  void initState() {
    super.initState();
    _load();
    _unbind = ScrollRealtime().bind('thread_comments', _load);
  }

  @override
  void dispose() {
    _unbind?.call();
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final res = await _getJson(
      'collections/thread_comments/records?limit=500${_q({'parent_collection': widget.parentCollection, 'parent_id': widget.parentId})}',
    );
    if (!mounted) return;
    final body = res['body'];
    setState(() {
      if (res['status'] != 200 || body is! Map) {
        _error = res['status'] == 404
            ? 'Comments aren\'t installed on this server.'
            : 'Could not load comments (${_failure(res)})';
      } else {
        _comments =
            (body['records'] as List? ?? const []).whereType<Map>().toList()
              ..sort(
                (a, b) => '${a['created_at']}'.compareTo('${b['created_at']}'),
              );
        _error = null;
      }
    });
  }

  Future<void> _post() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    final res = await ScrollAPI()
        .createUserCollectionRecord('thread_comments', {
          'parent_collection': widget.parentCollection,
          'parent_id': widget.parentId,
          'body': text,
        });
    if (!mounted) return;
    if (res['status'] is int && (res['status'] as int) < 300) {
      _text.clear();
      await _load();
    } else {
      _toast(context, 'Comment failed (${_failure(res)})');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ErrorCard(_error!);
    final list = _comments;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Comments', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (list == null)
            const LinearProgressIndicator(minHeight: 2)
          else if (list.isEmpty)
            const Text(
              'No comments yet.',
              style: TextStyle(color: Colors.white54),
            )
          else
            for (final c in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${c['owner_id'] ?? c['author'] ?? ''} · ${formatValue('created_at', null, c['created_at'])}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white38,
                      ),
                    ),
                    SelectableText('${c['body'] ?? ''}'),
                  ],
                ),
              ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  decoration: const InputDecoration(
                    hintText: 'Write a comment…',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _post(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _post, child: const Text('Post')),
            ],
          ),
        ],
      ),
    );
  }
}

class ReaderBlockView extends StatefulWidget {
  final String url;
  const ReaderBlockView({super.key, required this.url});

  @override
  State<ReaderBlockView> createState() => _ReaderBlockViewState();
}

class _ReaderBlockViewState extends State<ReaderBlockView> {
  Map? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ScrollAPI();
    final res = await api.rawRequest(
      'POST',
      '${api.objectServerUrl}api/read',
      data: {'url': widget.url},
    );
    if (!mounted) return;
    final body = res['body'];
    setState(() {
      if (res['status'] != 200 || body is! Map || body['status'] == 'error') {
        _error = body is Map && body['error'] != null
            ? '${body['error']}'
            : 'could not read page';
      } else {
        _data = body;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ErrorCard(_error!);
    final d = _data;
    if (d == null) return const _Panel(child: Text('Fetching…'));
    final paras = '${d['text'] ?? ''}'
        .split('\n\n')
        .where((p) => p.trim().isNotEmpty);
    final links = (d['links'] as List? ?? const []).whereType<Map>();
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${d['title'] ?? widget.url}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          for (final p in paras)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SelectableText(p.trim()),
            ),
          for (final l in links)
            SelectableText(
              '${l['n']}. ${l['label']} — ${l['href']}',
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
        ],
      ),
    );
  }
}
