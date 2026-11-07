// Schema diagram drawn from the connected server's real schemas: one box per
// collection, an arrow for every field with `relation: {collection, ...}`.
// (Replaces a hardcoded contacts/orders/invoices picture.)

import 'package:flutter/material.dart';

import 'api.dart';

class DiagramField {
  final String name;
  final String type;
  final String? relatesTo;
  const DiagramField(this.name, this.type, [this.relatesTo]);
}

class DiagramNode {
  final String name;
  final String title;
  final List<DiagramField> fields;
  const DiagramNode(this.name, this.title, this.fields);
}

class DiagramEdge {
  final String from;
  final String field;
  final String to;
  const DiagramEdge(this.from, this.field, this.to);
}

class SchemaGraph {
  final List<DiagramNode> nodes;
  final List<DiagramEdge> edges;

  /// Targets of relations that have no schema here (package not installed).
  final Set<String> missing;
  const SchemaGraph(this.nodes, this.edges, this.missing);

  bool isConnected(String name) =>
      edges.any((e) => e.from == name || e.to == name);
}

/// Build the graph from full schema maps ({name, title, fields: [...]}).
/// `fields` may be a list of {name, type, relation?} or a {name: spec} map.
SchemaGraph buildSchemaGraph(List<Map<String, dynamic>> schemas) {
  final nodes = <DiagramNode>[];
  final edges = <DiagramEdge>[];
  for (final s in schemas) {
    final name = (s['name'] ?? s['collection'] ?? '').toString();
    if (name.isEmpty) continue;
    final raw = s['fields'];
    final entries = <MapEntry<String, dynamic>>[
      if (raw is List)
        for (final f in raw.whereType<Map>())
          MapEntry((f['name'] ?? '').toString(), f),
      if (raw is Map)
        for (final e in raw.entries) MapEntry(e.key.toString(), e.value),
    ];
    final fields = <DiagramField>[];
    for (final e in entries) {
      if (e.key.isEmpty) continue;
      final spec = e.value is Map ? e.value as Map : const {};
      final rel = spec['relation'];
      final target = rel is Map ? rel['collection']?.toString() : null;
      fields.add(DiagramField(e.key, (spec['type'] ?? '').toString(), target));
      if (target != null && target.isNotEmpty) {
        edges.add(DiagramEdge(name, e.key, target));
      }
    }
    nodes.add(DiagramNode(name, (s['title'] ?? name).toString(), fields));
  }
  final names = nodes.map((n) => n.name).toSet();
  final missing = edges.map((e) => e.to).where((t) => !names.contains(t));
  // Related collections first (most links first), then the rest by name.
  int links(String n) => edges.where((e) => e.from == n || e.to == n).length;
  nodes.sort((a, b) {
    final d = links(b.name).compareTo(links(a.name));
    return d != 0 ? d : a.name.compareTo(b.name);
  });
  return SchemaGraph(nodes, edges, missing.toSet());
}

class SchemaDiagramView extends StatefulWidget {
  const SchemaDiagramView({super.key});

  @override
  State<SchemaDiagramView> createState() => _SchemaDiagramViewState();
}

class _SchemaDiagramViewState extends State<SchemaDiagramView> {
  SchemaGraph? _graph;
  String? _error;
  bool _loading = true;
  bool _onlyRelated = true;
  final _transform = TransformationController();

  static const _boxWidth = 230.0;
  static const _rowHeight = 20.0;
  static const _headerHeight = 34.0;
  static const _maxRows = 10;
  static const _gapX = 90.0;
  static const _gapY = 40.0;
  static const _columns = 4;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = ScrollAPI();
    final list = await api.listAdminSchemas();
    if (!mounted) return;
    if (list.isEmpty) {
      setState(() {
        _loading = false;
        _error = api.adminLocked.value
            ? 'Locked: reading schemas needs an admin sign-in.'
            : 'No schemas on this server.';
      });
      return;
    }
    final names = [
      for (final s in list)
        if (s is Map) (s['name'] ?? s['collection'] ?? '').toString(),
    ].where((n) => n.isNotEmpty).toList();
    final full = await Future.wait(names.map(api.getAdminSchema));
    if (!mounted) return;
    setState(() {
      _graph = buildSchemaGraph([
        for (var i = 0; i < names.length; i++) {'name': names[i], ...?full[i]},
      ]);
      _loading = false;
    });
  }

  double _boxHeight(DiagramNode n) =>
      _headerHeight +
      _rowHeight * (n.fields.length.clamp(0, _maxRows) + 1) +
      (n.fields.length > _maxRows ? _rowHeight : 0);

  Map<String, Rect> _layout(List<DiagramNode> nodes) {
    final rects = <String, Rect>{};
    var y = 24.0;
    for (var i = 0; i < nodes.length; i += _columns) {
      final row = nodes.skip(i).take(_columns).toList();
      var rowHeight = 0.0;
      for (var c = 0; c < row.length; c++) {
        final h = _boxHeight(row[c]);
        rects[row[c].name] = Rect.fromLTWH(
          24 + c * (_boxWidth + _gapX),
          y,
          _boxWidth,
          h,
        );
        if (h > rowHeight) rowHeight = h;
      }
      y += rowHeight + _gapY;
    }
    return rects;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: Colors.white54)),
      );
    }
    final graph = _graph!;
    final nodes = _onlyRelated
        ? graph.nodes.where((n) => graph.isConnected(n.name)).toList()
        : graph.nodes;
    final rects = _layout(nodes);
    final width =
        24 + _columns * (_boxWidth + _gapX) + 24; // room for edge labels
    final height =
        rects.values.fold<double>(0, (m, r) => r.bottom > m ? r.bottom : m) +
        40;
    final related = graph.nodes.where((n) => graph.isConnected(n.name)).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${graph.nodes.length} collections · ${graph.edges.length} relations',
                style: const TextStyle(color: Colors.white70),
              ),
              FilterChip(
                label: Text('Only related ($related)'),
                selected: _onlyRelated,
                onSelected: (v) => setState(() => _onlyRelated = v),
              ),
              if (graph.missing.isNotEmpty)
                Text(
                  'Not installed: ${(graph.missing.toList()..sort()).join(', ')}',
                  style: const TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 12,
                  ),
                ),
              IconButton(
                tooltip: 'Reset zoom',
                icon: const Icon(Icons.fit_screen_outlined, size: 18),
                onPressed: () => _transform.value = Matrix4.identity(),
              ),
              IconButton(
                tooltip: 'Reload schemas',
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: _load,
              ),
            ],
          ),
        ),
        Expanded(
          child: nodes.isEmpty
              ? const Center(
                  child: Text(
                    'No relations between collections. Turn off "Only related" to see them all.',
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              : InteractiveViewer(
                  transformationController: _transform,
                  constrained: false,
                  minScale: 0.3,
                  maxScale: 2.5,
                  boundaryMargin: const EdgeInsets.all(200),
                  child: SizedBox(
                    width: width,
                    height: height,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _EdgePainter(
                              graph.edges,
                              rects,
                              {for (final n in nodes) n.name: n},
                              _headerHeight,
                              _rowHeight,
                              _maxRows,
                            ),
                          ),
                        ),
                        for (final n in nodes)
                          Positioned.fromRect(
                            rect: rects[n.name]!,
                            child: _box(context, n, graph),
                          ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _box(BuildContext context, DiagramNode n, SchemaGraph graph) {
    final color = graph.isConnected(n.name)
        ? Theme.of(context).colorScheme.primary
        : Colors.white38;
    final shown = n.fields.take(_maxRows).toList();
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E26),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: _headerHeight,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.table_rows_outlined, size: 14, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    n.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w600, color: color),
                  ),
                ),
                Text(
                  '${n.fields.length}',
                  style: const TextStyle(fontSize: 11, color: Colors.white38),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          for (final f in shown)
            SizedBox(
              height: _rowHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Icon(
                      f.relatesTo != null ? Icons.link : Icons.remove,
                      size: 12,
                      color: f.relatesTo != null
                          ? Colors.lightBlueAccent
                          : Colors.white24,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        f.relatesTo != null
                            ? '${f.name} → ${f.relatesTo}'
                            : f.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: f.relatesTo != null
                              ? Colors.lightBlueAccent
                              : Colors.white70,
                        ),
                      ),
                    ),
                    Text(
                      f.type,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white30,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (n.fields.length > _maxRows)
            SizedBox(
              height: _rowHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  '+ ${n.fields.length - _maxRows} more',
                  style: const TextStyle(fontSize: 11, color: Colors.white38),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EdgePainter extends CustomPainter {
  final List<DiagramEdge> edges;
  final Map<String, Rect> rects;
  final Map<String, DiagramNode> nodes;
  final double headerHeight;
  final double rowHeight;
  final int maxRows;
  _EdgePainter(
    this.edges,
    this.rects,
    this.nodes,
    this.headerHeight,
    this.rowHeight,
    this.maxRows,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.lightBlueAccent.withValues(alpha: 0.55)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (final e in edges) {
      final from = rects[e.from];
      final to = rects[e.to];
      if (from == null || to == null) continue;
      final idx = nodes[e.from]!.fields.indexWhere((f) => f.name == e.field);
      final rowY =
          from.top +
          headerHeight +
          4 +
          rowHeight * (idx.clamp(0, maxRows - 1) + 0.5);
      final rightward = to.center.dx >= from.center.dx;
      final start = Offset(rightward ? from.right : from.left, rowY);
      final end = e.from == e.to
          ? Offset(from.right, from.top + headerHeight / 2)
          : Offset(rightward ? to.left : to.right, to.top + headerHeight / 2);
      final bend = e.from == e.to ? 40.0 : (end.dx - start.dx).abs() / 2 + 20;
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(
          start.dx + (rightward ? bend : -bend),
          start.dy,
          end.dx +
              (rightward || e.from == e.to ? -bend : bend) *
                  (e.from == e.to ? -1 : 1),
          end.dy,
          end.dx,
          end.dy,
        );
      canvas.drawPath(path, paint);
      canvas.drawCircle(end, 3, paint..style = PaintingStyle.fill);
      paint.style = PaintingStyle.stroke;
    }
  }

  @override
  bool shouldRepaint(_EdgePainter old) =>
      old.edges != edges || old.rects != rects;
}
