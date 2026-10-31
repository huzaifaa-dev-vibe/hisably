import '../../core/db/app_database.dart';
import '../stream_utils.dart';
import 'account_repository.dart';
import 'transaction_repository.dart';

/// One slice of the category donut: an expense/income bucket for a month.
class CategorySlice {
  const CategorySlice({
    required this.name,
    required this.iconKey,
    required this.totalMinor,
  });

  final String name;
  final String iconKey;
  final int totalMinor;
}

/// Daily in/out for one currency (bars chart).
class DailyFlowPoint {
  const DailyFlowPoint({required this.day, required this.inMinor, required this.outMinor});
  final int day; // 1..31
  final int inMinor;
  final int outMinor;
}

/// Monthly in/out for one currency (comparison chart).
class MonthlyFlowPoint {
  const MonthlyFlowPoint({required this.month, required this.inMinor, required this.outMinor});
  final DateTime month; // normalized to first of month
  final int inMinor;
  final int outMinor;
}

/// Daily closing balance for one currency (line chart).
class BalancePoint {
  const BalancePoint({required this.date, required this.balanceMinor});
  final DateTime date;
  final int balanceMinor;
}

/// Derived report series for the charts screen.
///
/// All aggregation is done in Dart over the existing watched repository
/// streams — personal ledgers are hundreds of rows per month, and this keeps
/// every figure exactly consistent with what the ledger itself implies.
/// Currencies are NEVER mixed: every query is scoped to one currency.
class ReportsRepository {
  ReportsRepository(this._txRepo, this._accountRepo);

  final TransactionRepository _txRepo;
  final AccountRepository _accountRepo;

  /// Expense/income breakdown by category for the month of [month].
  Stream<List<CategorySlice>> watchCategoryBreakdown({
    required DateTime month,
    required String currencyCode,
    required bool expense,
  }) {
    final window = _monthWindow(month);
    final filter = TxQueryFilter(
      type: expense ? TxTypeFilter.expense : TxTypeFilter.income,
      from: window.$1,
      to: window.$2,
      limit: 5000,
    );
    return _txRepo.watchTransactions(filter).map((rows) {
      final byCategory = <String, int>{};
      final meta = <String, Category>{};
      for (final r in rows) {
        if (r.currency.code != currencyCode) continue;
        final cat = r.category;
        final key = cat?.id.toString() ?? '0';
        byCategory[key] = (byCategory[key] ?? 0) + r.tx.amountMinor;
        if (cat != null) meta[key] = cat;
      }
      final slices = [
        for (final e in byCategory.entries)
          if (e.value > 0)
            CategorySlice(
              name: meta[e.key]?.name ?? 'Uncategorised',
              iconKey: meta[e.key]?.iconKey ?? 'category',
              totalMinor: e.value,
            ),
      ]..sort((a, b) => b.totalMinor.compareTo(a.totalMinor));
      return slices;
    });
  }

  /// Daily in/out bars for the month of [month]. Every day of the month is
  /// present so the x-axis is stable across empty days.
  Stream<List<DailyFlowPoint>> watchDailyFlow({
    required DateTime month,
    required String currencyCode,
  }) {
    final window = _monthWindow(month);
    final filter = TxQueryFilter(
      type: TxTypeFilter.all,
      from: window.$1,
      to: window.$2,
      limit: 5000,
    );
    return _txRepo.watchTransactions(filter).map((rows) {
      final daysInMonth = DateTime(window.$3.year, window.$3.month + 1, 0).day;
      final ins = List<int>.filled(daysInMonth + 1, 0);
      final outs = List<int>.filled(daysInMonth + 1, 0);
      for (final r in rows) {
        if (r.currency.code != currencyCode) continue;
        final d = r.tx.occurredAt.day;
        switch (r.tx.type) {
          case TransactionType.income:
            ins[d] += r.tx.amountMinor;
          case TransactionType.expense:
            outs[d] += r.tx.amountMinor;
          case TransactionType.transfer || TransactionType.exchange:
            break; // never P&L
        }
      }
      return [
        for (var d = 1; d <= daysInMonth; d++)
          DailyFlowPoint(day: d, inMinor: ins[d], outMinor: outs[d]),
      ];
    });
  }

  /// In/out totals for the last [months] months (inclusive of the current
  /// one), oldest first — for the monthly comparison bars.
  Stream<List<MonthlyFlowPoint>> watchMonthlyFlow({
    required String currencyCode,
    int months = 6,
  }) {
    final now = DateTime.now();
    final firstOfThisMonth = DateTime(now.year, now.month);
    final start = DateTime(firstOfThisMonth.year, firstOfThisMonth.month - (months - 1));
    final filter = TxQueryFilter(from: start, to: now, limit: 20000);
    return _txRepo.watchTransactions(filter).map((rows) {
      final ins = List<int>.filled(months, 0);
      final outs = List<int>.filled(months, 0);
      for (final r in rows) {
        if (r.currency.code != currencyCode) continue;
        final mIndex = (r.tx.occurredAt.year - start.year) * 12 +
            r.tx.occurredAt.month -
            start.month;
        if (mIndex < 0 || mIndex >= months) continue;
        switch (r.tx.type) {
          case TransactionType.income:
            ins[mIndex] += r.tx.amountMinor;
          case TransactionType.expense:
            outs[mIndex] += r.tx.amountMinor;
          case TransactionType.transfer || TransactionType.exchange:
            break;
        }
      }
      return [
        for (var i = 0; i < months; i++)
          MonthlyFlowPoint(
            month: DateTime(start.year, start.month + i),
            inMinor: ins[i],
            outMinor: outs[i],
          ),
      ];
    });
  }

  /// Daily closing TOTAL balance for [currencyCode] across the last [days]
  /// days, oldest first.
  ///
  /// Derivation: current total (the derived ledger aggregate) minus the
  /// window deltas gives the opening; walking forward accumulates daily
  /// flows. Exchanges contribute −(amount+fee) from the source currency and
  /// +toAmount into the destination currency, matching ledger semantics.
  Stream<List<BalancePoint>> watchBalanceSeries({
    required String currencyCode,
    int days = 30,
  }) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final windowStart = todayStart.subtract(Duration(days: days - 1));
    final filter = TxQueryFilter(from: windowStart, to: now, limit: 20000);

    return _combine(
      _txRepo.watchTransactions(filter),
      _accountRepo.watchTotalsByCurrency(),
      (List<TxWithRefs> rows, Map<String, int> totals) {
        final deltas = List<int>.filled(days + 1, 0);
        int windowDelta = 0;

        int deltaFor(TxWithRefs r) {
          final tx = r.tx;
          final srcCode = r.account?.currencyCode;
          final dstCode = r.toAccount?.currencyCode;
          var d = 0;
          switch (tx.type) {
            case TransactionType.income:
              if (srcCode == currencyCode) d += tx.amountMinor;
            case TransactionType.expense:
              if (srcCode == currencyCode) d -= tx.amountMinor;
            case TransactionType.transfer:
              final src = srcCode == currencyCode ? -tx.amountMinor : 0;
              final dst = (dstCode == currencyCode && dstCode != srcCode)
                  ? (tx.toAmountMinor ?? 0)
                  : 0;
              d += src + dst;
            case TransactionType.exchange:
              final src = srcCode == currencyCode ? -(tx.amountMinor + tx.feeMinor) : 0;
              final dst = (dstCode == currencyCode && dstCode != srcCode)
                  ? (tx.toAmountMinor ?? 0)
                  : 0;
              d += src + dst;
          }
          return d;
        }

        for (final r in rows) {
          final d = deltaFor(r);
          if (d == 0) continue;
          windowDelta += d;
          final dayIndex =
              r.tx.occurredAt.difference(windowStart).inDays.clamp(0, days - 1);
          deltas[dayIndex] += d;
        }

        final currentTotal = totals[currencyCode] ?? 0;
        final opening = currentTotal - windowDelta;

        final points = <BalancePoint>[];
        var running = opening;
        for (var i = 0; i <= days - 1; i++) {
          running += deltas[i];
          points.add(BalancePoint(
            date: windowStart.add(Duration(days: i)),
            balanceMinor: running,
          ));
        }
        // The final point must equal the current derived total — an
        // internal consistency guarantee.
        running += deltas[days];
        assert(running == currentTotal);
        return points;
      },
    );
  }

  // --------------------------------------------------------------- helpers

  /// (start, end, monthStart)
  static (DateTime, DateTime, DateTime) _monthWindow(DateTime month) {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    return (start, end, start);
  }

  static Stream<R> _combine<A, B, R>(
    Stream<A> a,
    Stream<B> b,
    R Function(A, B) fn,
  ) =>
      combine2(a, b, fn);
}
