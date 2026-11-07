// Query: pick a collection, filter/sort its real records, export CSV.
// The object server has no SQL endpoint; records come from the paged
// records API and the filter runs here. (Replaces a mock SQL screen whose
// results were hardcoded.)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'home_collections.dart';

/// One condition. Forms: `field=value`, `field!=value`, `field~text`
/// (contains), `field>n`, `field<n`, or bare text (any field contains).
class QueryCondition {
  final String? field;
  final String op;
  final String value;
  const QueryCondition(this.field, this.op, this.value);

  static final _pattern = RegExp(
    r'^\s*([A-Za-z_][\w.]*)\s*(!=|=|~|>|<)\s*(.*)$',
  );

  static QueryCondition parse(String term) {
    final m = _pattern.firstMatch(term);
    if (m == null) return QueryCondition(null, '~', term.trim());
    return QueryCondition(m[1], m[2]!, m[3]!.trim());
  }

  bool matches(Map<String, dynamic> row) {
    final needle = value.toLowerCase();
    if (field == null) {
      return row.values.any((v) => '${v ?? ''}'.toLowerCase().contains(needle));
    }
    final raw = row[field];
    final text = raw == null ? '' : '$raw';
    switch (op) {
      case '=':
        return text.toLowerCase() == needle;
      case '!=':
        return text.toLowerCase() != needle;
      case '~':
        return text.toLowerCase().contains(needle);
      case '>':
      case '<':
        if (raw == null) return false; // missing is neither bigger nor smaller
        final a = num.tryParse(text);
        final b = num.tryParse(value);
        if (a != null && b != null) return op == '>' ? a > b : a < b;
        final c = text.compareTo(value); // ISO dates compare as text
        return op == '>' ? c > 0 : c < 0;
    }
    return false;
  }
}

/// Conditions are joined with " and " (case-insensitive) or ";".
List<QueryCondition> parseQueryFilter(String filter) => filter
    .split(RegExp(r'\s+and\s+|;', caseSensitive: false))
    .where((t) => t.trim().isNotEmpty)
    .map(QueryCondition.parse)
    .toList();

List<Map<String, dynamic>> runQuery(
  List<Map<String, dynamic>> rows, {
  String filter = '',
  String? sortField,
  bool descending = false,
}) {
  final conds = parseQueryFilter(filter);
  final out = rows.where((r) => conds.every((c) => c.matches(r))).toList();
  if (sortField != null && sortField.isNotEmpty) {
    int cmp(Map<String, dynamic> a, Map<String, dynamic> b) {
      final x = a[sortField], y = b[sortField];
      // Missing values go last in either direction.
      if (x == null && y == null) return 0;
      if (x == null) return 1;
      if (y == null) return -1;
      final nx = num.tryParse('$x'), ny = num.tryParse('$y');
      final c = nx != null && ny != null
          ? nx.compareTo(ny)
          : '$x'.compareTo('$y');
      return descending ? -c : c;
    }

    out.sort(cmp);
  }
  return out;
}

/// Column order: id first, then keys in order of first appearance.
List<String> queryColumns(List<Map<String, dynamic>> rows) {
  final cols = <String>[];
  for (final r in rows) {
    for (final k in r.keys) {
      if (!cols.contains(k)) cols.add(k);
    }
  }
  if (cols.remove('id')) cols.insert(0, 'id');
  return cols;
}

String toCsv(List<Map<String, dynamic>> rows, List<String> columns) {
  String cell(Object? v) {
    final s = v == null ? '' : '$v';
    return RegExp(r'[",\n\r]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  return [
    columns.map(cell).join(','),
    for (final r in rows) columns.map((c) => cell(r[c])).join(','),
  ].join('\n');
}

class QueryView extends StatefulWidget {
  /// Preselect this collection; with [autoRun], load it immediately.
  final String? initialCollection;
  final bool autoRun;
  const QueryView({super.key, this.initialCollection, this.autoRun = false});

  @override
  State<QueryView> createState() => _QueryViewState();
}

class _QueryViewState extends State<QueryView> {
  final _filter = TextEditingController();
  List<String> _collections = [];
  String? _collection;
  int _max = 500;
  List<Map<String, dynamic>> _rows = [];
  int? _total;
  String? _sortField;
  bool _descending = false;
  bool _loading = false;
  String? _message;
  Duration? _took;

  @override
  void initState() {
    super.initState();
    _collection = widget.initialCollection;
    _loadCollections();
    if (widget.autoRun && widget.initialCollection != null) _run();
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  Future<void> _loadCollections() async {
    final api = ScrollAPI();
    final list = await api.listAdminCollections();
    if (!mounted) return;
    final names = <String>[
      for (final c in list)
        // Object namespaces (no schema, no records) hold objects, not rows.
        if (c is Map && (c['has_schema'] != false || c['has_records'] != false))
          (c['name'] ?? c['collection'] ?? '').toString()
        else if (c is String)
          c,
    ].where((n) => n.isNotEmpty).toList()..sort();
    // A user key can't list collections; keep the one we were opened on.
    if (_collection != null && !names.contains(_collection)) {
      names.insert(0, _collection!);
    }
    setState(() {
      _collections = names;
      _collection ??= names.contains('notes') ? 'notes' : names.firstOrNull;
      if (names.isEmpty) {
        _message = api.adminLocked.value
            ? 'Locked: listing collections needs an admin sign-in.'
            : 'No collections on this server.';
      }
    });
  }

  Future<void> _run() async {
    final name = _collection;
    if (name == null) return;
    setState(() {
      _loading = true;
      _message = null;
    });
    final api = ScrollAPI();
    final started = DateTime.now();
    final rows = <Map<String, dynamic>>[];
    int? total;
    String? error;
    final seg = Uri.encodeComponent(name);
    var useAdmin = true;
    while (rows.length < _max) {
      final page = (_max - rows.length).clamp(1, 200);
      final path = useAdmin
          ? 'admin/collections/$seg/records'
          : 'collections/$seg/records';
      final res = await api.rawRequest(
        'GET',
        '${api.objectServerUrl}$path?limit=$page&offset=${rows.length}',
      );
      final status = res['status'];
      if (useAdmin && (status == 401 || status == 403) && rows.isEmpty) {
        useAdmin = false; // a key/session may still read via the user route
        continue;
      }
      final body = res['body'];
      if (status is! int || status >= 300 || body is! Map) {
        error = httpFailure(status, res['error']);
        break;
      }
      final page0 = (body['records'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      total = (body['total'] as num?)?.toInt() ?? total;
      rows.addAll(page0);
      if (page0.length < page || body['has_more'] == false) break;
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _rows = rows;
      _total = total;
      _took = DateTime.now().difference(started);
      _message = error;
      if (_sortField != null && !queryColumns(rows).contains(_sortField)) {
        _sortField = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = runQuery(
      _rows,
      filter: _filter.text,
      sortField: _sortField,
      descending: _descending,
    );
    final columns = queryColumns(_rows);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  initialValue: _collection,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Collection',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final c in _collections)
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: (v) => setState(() {
                    _collection = v;
                    _rows = [];
                    _total = null;
                  }),
                ),
              ),
              SizedBox(
                width: 380,
                child: TextField(
                  controller: _filter,
                  decoration: const InputDecoration(
                    labelText: 'Filter',
                    hintText: 'status=open and priority>2   ·   title~invoice',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _run(),
                ),
              ),
              DropdownButton<int>(
                value: _max,
                items: const [
                  DropdownMenuItem(value: 100, child: Text('100 rows')),
                  DropdownMenuItem(value: 500, child: Text('500 rows')),
                  DropdownMenuItem(value: 2000, child: Text('2000 rows')),
                ],
                onChanged: (v) => setState(() => _max = v ?? 500),
              ),
              FilledButton.icon(
                onPressed: _loading || _collection == null ? null : _run,
                icon: const Icon(Icons.play_arrow, size: 16),
                label: const Text('Run'),
              ),
              OutlinedButton.icon(
                onPressed: _collection == null
                    ? null
                    : () async {
                        final id = await createServerRecord(
                          context,
                          _collection!,
                        );
                        if (id != null && mounted) await _run();
                      },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New'),
              ),
              OutlinedButton.icon(
                onPressed: result.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(
                          ClipboardData(text: toCsv(result, columns)),
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Copied ${result.length} rows as CSV',
                            ),
                          ),
                        );
                      },
                icon: const Icon(Icons.copy, size: 14),
                label: const Text('Copy CSV'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            _loading
                ? 'Loading…'
                : _message ??
                      (_took == null
                          ? 'Pick a collection and press Run. Filters and sorting run on the loaded records.'
                          : '${result.length} of ${_rows.length} loaded rows match'
                                '${_total != null && _total! > _rows.length ? ' (collection has $_total; raise the row limit to load more)' : ''}'
                                ' · loaded in ${_took!.inMilliseconds} ms'),
            style: TextStyle(
              fontSize: 12,
              color: _message != null ? Colors.orangeAccent : Colors.white60,
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1),
        Expanded(
          child: _rows.isEmpty
              ? Center(
                  child: Text(
                    _took == null ? '' : 'No records in $_collection.',
                    style: const TextStyle(color: Colors.white54),
                  ),
                )
              : Scrollbar(
                  child: SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        showCheckboxColumn: false,
                        headingRowHeight: 36,
                        dataRowMinHeight: 30,
                        dataRowMaxHeight: 30,
                        sortColumnIndex: _sortField == null
                            ? null
                            : columns.indexOf(_sortField!),
                        sortAscending: !_descending,
                        columns: [
                          for (final c in columns)
                            DataColumn(
                              label: Text(c),
                              onSort: (_, _) => setState(() {
                                if (_sortField == c) {
                                  _descending = !_descending;
                                } else {
                                  _sortField = c;
                                  _descending = false;
                                }
                              }),
                            ),
                        ],
                        rows: [
                          for (final r in result.take(1000))
                            DataRow(
                              // Click a row: view it, then Edit or Delete.
                              onSelectChanged: (_) async {
                                final changed = await showServerRecord(
                                  context,
                                  _collection!,
                                  r,
                                );
                                if (changed && mounted) await _run();
                              },
                              cells: [
                                for (final c in columns)
                                  DataCell(
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 280,
                                      ),
                                      child: Text(
                                        r[c] == null ? '' : '${r[c]}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
