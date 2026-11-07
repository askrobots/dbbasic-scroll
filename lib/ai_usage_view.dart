import 'package:flutter/material.dart';

import 'api.dart';

/// Totals for one model (or provider/model pair).
class AiUsageModelRow {
  final String model;
  int calls = 0;
  int tokensIn = 0;
  int tokensOut = 0;
  int costCents = 0;
  AiUsageModelRow(this.model);
}

class AiUsageDay {
  final DateTime day; // local midnight
  int calls = 0;
  int costCents = 0;
  AiUsageDay(this.day);
}

/// Aggregates of the `ai_usage` collection: one append-only row per AI chat
/// call with provider, model, tokens_in, tokens_out, cost_cents (null when no
/// price matched) and created_at. Only numbers and model names — no prompt or
/// answer text ever reaches this screen.
class AiUsageSummary {
  int calls = 0;
  int tokensIn = 0;
  int tokensOut = 0;
  int costCents = 0; // sum of rows that had a price
  int unpricedCalls = 0; // rows whose cost_cents was null
  int undatedCalls = 0; // rows with no parsable created_at
  DateTime? firstAt; // oldest created_at (local)
  DateTime? lastAt; // newest created_at (local)
  final List<AiUsageModelRow> byModel = [];
  final List<AiUsageDay> byDay = []; // oldest → newest, zero days included

  double get costDollars => costCents / 100;
}

int? _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is String) return int.tryParse(v) ?? num.tryParse(v)?.round();
  return null;
}

/// Summarise [rows]. [days] most recent days (ending at [now]'s local date)
/// are returned in `byDay`; rows without a parsable timestamp still count in
/// the totals.
AiUsageSummary summarizeAiUsage(
  Iterable<Map<String, dynamic>> rows, {
  DateTime? now,
  int days = 14,
}) {
  final today = (now ?? DateTime.now()).toLocal();
  final start = DateTime(today.year, today.month, today.day);
  final summary = AiUsageSummary();
  final dayBuckets = <DateTime, AiUsageDay>{
    for (var i = days - 1; i >= 0; i--)
      DateTime(start.year, start.month, start.day - i): AiUsageDay(
        DateTime(start.year, start.month, start.day - i),
      ),
  };
  final models = <String, AiUsageModelRow>{};

  for (final row in rows) {
    final tin = _asInt(row['tokens_in']) ?? 0;
    final tout = _asInt(row['tokens_out']) ?? 0;
    final cost = _asInt(row['cost_cents']);
    final provider = (row['provider'] ?? '').toString();
    final model = (row['model'] ?? 'unknown').toString();
    final key = provider.isEmpty ? model : '$provider / $model';

    summary.calls++;
    summary.tokensIn += tin;
    summary.tokensOut += tout;
    if (cost == null) {
      summary.unpricedCalls++;
    } else {
      summary.costCents += cost;
    }

    final m = models.putIfAbsent(key, () => AiUsageModelRow(key));
    m.calls++;
    m.tokensIn += tin;
    m.tokensOut += tout;
    m.costCents += cost ?? 0;

    final created = DateTime.tryParse((row['created_at'] ?? '').toString());
    if (created == null) {
      summary.undatedCalls++;
    } else {
      final local = created.toLocal();
      if (summary.firstAt == null || local.isBefore(summary.firstAt!)) {
        summary.firstAt = local;
      }
      if (summary.lastAt == null || local.isAfter(summary.lastAt!)) {
        summary.lastAt = local;
      }
      final bucket = dayBuckets[DateTime(local.year, local.month, local.day)];
      if (bucket != null) {
        bucket.calls++;
        bucket.costCents += cost ?? 0;
      }
    }
  }

  summary.byModel.addAll(
    models.values.toList()..sort((a, b) {
      final byCost = b.costCents.compareTo(a.costCents);
      return byCost != 0 ? byCost : b.calls.compareTo(a.calls);
    }),
  );
  summary.byDay.addAll(dayBuckets.values);
  return summary;
}

/// Read-only AI cost screen over the caller's own `ai_usage` rows.
class AIUsageView extends StatefulWidget {
  const AIUsageView({super.key});

  @override
  State<AIUsageView> createState() => _AIUsageViewState();
}

class _AIUsageViewState extends State<AIUsageView> {
  static const _limit = 1000;
  bool _loading = true;
  String? _error;
  AiUsageSummary? _summary;
  int _rowCount = 0;
  int? _total; // server-reported total, when it exceeds what we fetched

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await ScrollAPI().listUserCollectionRecords(
      'ai_usage',
      limit: _limit,
    );
    if (!mounted) return;
    final status = result['status'];
    if (status == 404) {
      setState(() {
        _loading = false;
        _summary = null;
        _error =
            'This server has no ai_usage collection (the app-shell '
            'package records AI cost there).';
      });
      return;
    }
    if (status is! int || status < 200 || status >= 300) {
      setState(() {
        _loading = false;
        _error = httpFailure(status, result['error']);
      });
      return;
    }
    final body = result['body'];
    final raw = body is Map ? body['records'] : body;
    final rows = <Map<String, dynamic>>[
      if (raw is List)
        for (final r in raw)
          if (r is Map) Map<String, dynamic>.from(r),
    ];
    setState(() {
      _loading = false;
      _rowCount = rows.length;
      _total = body is Map ? _asInt(body['total']) : null;
      _summary = summarizeAiUsage(rows);
    });
  }

  String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  String _rangeNote(AiUsageSummary s) {
    final inWindow = s.byDay.fold<int>(0, (a, d) => a + d.calls);
    final parts = <String>[
      if (s.firstAt != null && s.lastAt != null)
        'Calls span ${_date(s.firstAt!)} to ${_date(s.lastAt!)}',
      if (inWindow == 0 && s.calls > 0)
        'none in the last ${s.byDay.length} days',
      if (s.undatedCalls > 0)
        '${s.undatedCalls} call(s) have no timestamp, so they are not charted',
    ];
    return parts.isEmpty ? '' : '${parts.join('; ')}.';
  }

  String _money(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';

  String _compact(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }

  Widget _stat(String label, String value, {String? note}) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.white54),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          if (note != null) ...[
            const SizedBox(height: 2),
            Text(
              note,
              style: const TextStyle(fontSize: 11, color: Colors.white38),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'AI Usage',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(width: 10),
              const Chip(
                label: Text('READ ONLY', style: TextStyle(fontSize: 10)),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Tokens and cost per AI call. Numbers and model names only — '
            'no prompts or answers.',
            style: TextStyle(fontSize: 12, color: Colors.white38),
          ),
          const SizedBox(height: 20),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Colors.red[300], fontSize: 13),
            ),
          if (summary != null && summary.calls == 0)
            const Text(
              'No AI calls recorded yet.',
              style: TextStyle(color: Colors.white54),
            ),
          if (summary != null && summary.calls > 0) ...[
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _stat(
                  'Calls',
                  '${summary.calls}',
                  note: (_total ?? 0) > _rowCount
                      ? 'latest $_rowCount of $_total'
                      : null,
                ),
                _stat(
                  'Cost',
                  _money(summary.costCents),
                  note: summary.unpricedCalls > 0
                      ? '${summary.unpricedCalls} call(s) had no price'
                      : null,
                ),
                _stat('Tokens in', _compact(summary.tokensIn)),
                _stat('Tokens out', _compact(summary.tokensOut)),
              ],
            ),
            const SizedBox(height: 28),
            Text(
              'Last ${summary.byDay.length} days',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 10),
            _DayBars(days: summary.byDay),
            const SizedBox(height: 8),
            Text(
              _rangeNote(summary),
              style: const TextStyle(fontSize: 12, color: Colors.white38),
            ),
            const SizedBox(height: 28),
            Text('By model', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            for (final m in summary.byModel)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(m.model),
                subtitle: Text(
                  '${m.calls} calls · ${_compact(m.tokensIn)} in · '
                  '${_compact(m.tokensOut)} out',
                  style: const TextStyle(fontSize: 12, color: Colors.white38),
                ),
                trailing: Text(_money(m.costCents)),
              ),
          ],
        ],
      ),
    );
  }
}

/// Minimal daily bar chart (calls per day), no chart dependency.
class _DayBars extends StatelessWidget {
  final List<AiUsageDay> days;
  const _DayBars({required this.days});

  @override
  Widget build(BuildContext context) {
    final maxCalls = days.fold<int>(1, (a, d) => d.calls > a ? d.calls : a);
    return SizedBox(
      height: 110,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final d in days)
            Expanded(
              child: Tooltip(
                message:
                    '${d.day.month}/${d.day.day}: ${d.calls} calls, '
                    '\$${(d.costCents / 100).toStringAsFixed(2)}',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        height: d.calls == 0 ? 2 : 4 + 80 * d.calls / maxCalls,
                        decoration: BoxDecoration(
                          color: d.calls == 0
                              ? Colors.white12
                              : Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${d.day.day}',
                        style: const TextStyle(
                          fontSize: 9,
                          color: Colors.white38,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
