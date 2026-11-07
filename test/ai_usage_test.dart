import 'package:flutter_test/flutter_test.dart';

import 'package:dbbasic_scroll/ai_usage_view.dart';

void main() {
  // "Now" is mid-day so UTC/local conversions can't shift the date in CI.
  final now = DateTime(2026, 11, 6, 12);

  Map<String, dynamic> row({
    String provider = 'openai',
    String model = 'gpt-x',
    Object? tin = 100,
    Object? tout = 50,
    Object? cost = 10,
    String? at,
  }) => {
    'provider': provider,
    'model': model,
    'tokens_in': tin,
    'tokens_out': tout,
    'cost_cents': cost,
    'created_at': at ?? DateTime(2026, 11, 6, 9).toIso8601String(),
  };

  test('empty input gives zeroes and a full run of empty days', () {
    final s = summarizeAiUsage(const [], now: now);
    expect(s.calls, 0);
    expect(s.costCents, 0);
    expect(s.byDay, hasLength(14));
    expect(s.byDay.last.day, DateTime(2026, 11, 6));
    expect(s.byDay.first.day, DateTime(2026, 10, 24));
    expect(s.byModel, isEmpty);
  });

  test('totals, per-model rows sorted by cost, and unpriced calls', () {
    final s = summarizeAiUsage([
      row(model: 'big', cost: 300, tin: 1000, tout: 500),
      row(model: 'big', cost: 200),
      row(model: 'small', cost: 5),
      row(model: 'small', cost: null), // no ai_prices row matched
    ], now: now);
    expect(s.calls, 4);
    expect(s.costCents, 505);
    expect(s.costDollars, 5.05);
    expect(s.unpricedCalls, 1);
    expect(s.tokensIn, 1000 + 100 + 100 + 100);
    expect(s.byModel.map((m) => m.model), ['openai / big', 'openai / small']);
    expect(s.byModel.first.calls, 2);
    expect(s.byModel.first.costCents, 500);
  });

  test('values arrive as strings or doubles and still count', () {
    final s = summarizeAiUsage([
      row(tin: '120', tout: 30.0, cost: '7'),
      row(tin: 'garbage', tout: null, cost: 'x'),
    ], now: now);
    expect(s.tokensIn, 120); // garbage counts as 0, the call still counts
    expect(s.tokensOut, 30);
    expect(s.costCents, 7);
    expect(s.unpricedCalls, 1);
    expect(s.calls, 2);
  });

  test('rows land in the right day; old or undated rows only hit totals', () {
    final s = summarizeAiUsage([
      row(at: DateTime(2026, 11, 6, 8).toIso8601String(), cost: 10),
      row(at: DateTime(2026, 11, 6, 20).toIso8601String(), cost: 20),
      row(at: DateTime(2026, 11, 5, 23).toIso8601String(), cost: 1),
      row(at: DateTime(2026, 9, 1).toIso8601String(), cost: 99), // too old
      row(at: 'not a date', cost: 3),
    ], now: now);
    expect(s.byDay.last.calls, 2);
    expect(s.byDay.last.costCents, 30);
    expect(s.byDay[s.byDay.length - 2].calls, 1);
    expect(s.calls, 5);
    expect(s.costCents, 133);
    expect(s.byDay.fold<int>(0, (a, d) => a + d.calls), 3);
  });

  test('date range and undated rows are reported', () {
    final s = summarizeAiUsage([
      row(at: DateTime(2026, 9, 1, 10).toIso8601String()),
      row(at: DateTime(2026, 10, 2, 10).toIso8601String()),
      {'provider': 'p', 'model': 'm', 'tokens_in': 1, 'tokens_out': 1},
    ], now: now);
    expect(s.undatedCalls, 1);
    expect(s.firstAt, DateTime(2026, 9, 1, 10));
    expect(s.lastAt, DateTime(2026, 10, 2, 10));
    expect(s.byDay.fold<int>(0, (a, d) => a + d.calls), 0);
  });
}
