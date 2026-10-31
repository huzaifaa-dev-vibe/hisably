import 'package:drift/drift.dart';

import '../../core/db/app_database.dart';
import '../../data/stream_utils.dart';

/// A budget row enriched with its category and the spend DERIVED from the
/// ledger for a specific month. Nothing about progress is ever stored.
class BudgetWithSpent {
  const BudgetWithSpent({
    required this.budget,
    required this.category,
    required this.spentMinor,
  });

  final BudgetRow budget;
  final Category category;
  final int spentMinor;

  int get limitMinor => budget.monthlyLimitMinor;
  double get progress =>
      limitMinor <= 0 ? 0 : (spentMinor / limitMinor).clamp(0.0, 1.0);
  bool get isOver => spentMinor > limitMinor;

  /// ≥ 100 % → over (red), ≥ 80 % → warning (amber), else on track.
  BudgetState get state => isOver
      ? BudgetState.over
      : spentMinor >= limitMinor * 0.8
          ? BudgetState.warning
          : BudgetState.ok;
}

enum BudgetState { ok, warning, over }

/// The budget book. One limit per (category, currency). Spent totals are
/// computed from expense rows of the ledger — the single source of truth —
/// so deleting or editing a transaction updates progress instantly.
class BudgetRepository {
  BudgetRepository(this._db);

  final AppDatabase _db;

  /// All budgets with live spent totals for the month containing [month].
  Stream<List<BudgetWithSpent>> watchBudgetsWithSpent(DateTime month) {
    final (start, end) = _monthWindow(month);

    final budgets$ = (_db.select(_db.budgets)
          ..orderBy([(b) => OrderingTerm.asc(b.id)]))
        .watch();
    final categories$ = (_db.select(_db.categories)).watch();
    final spent$ = _watchSpentByCategoryAndCurrency(start, end);

    // Nest the two binary combinators: (budgets × categories) × spent.
    return combine2(
      combine2(budgets$, categories$,
          (List<BudgetRow> bs, List<Category> cs) => (bs, cs)),
      spent$,
      (pair, Map<String, int> spent) {
        final (budgets, categories) = pair;
        final byId = {for (final c in categories) c.id: c};
        return [
          for (final b in budgets)
            if (byId[b.categoryId] != null)
              BudgetWithSpent(
                budget: b,
                category: byId[b.categoryId]!,
                spentMinor: spent['${b.categoryId}:${b.currencyCode}'] ?? 0,
              ),
        ];
      },
    );
  }

  /// Upsert keyed by the unique (categoryId, currencyCode) index.
  Future<void> setLimit({
    required int categoryId,
    required String currencyCode,
    required int monthlyLimitMinor,
  }) async {
    if (monthlyLimitMinor <= 0) {
      throw ArgumentError.value(monthlyLimitMinor, 'monthlyLimitMinor',
          'Budget limit must be a positive amount in minor units');
    }
    final existing = await (_db.select(_db.budgets)
          ..where((b) => b.categoryId.equals(categoryId))
          ..where((b) => b.currencyCode.equals(currencyCode)))
        .getSingleOrNull();
    if (existing == null) {
      await _db.into(_db.budgets).insert(BudgetsCompanion.insert(
            categoryId: categoryId,
            currencyCode: currencyCode,
            monthlyLimitMinor: monthlyLimitMinor,
          ));
    } else {
      await (_db.update(_db.budgets)..where((b) => b.id.equals(existing.id)))
          .write(BudgetsCompanion(monthlyLimitMinor: Value(monthlyLimitMinor)));
    }
  }

  Future<void> delete(int id) =>
      (_db.delete(_db.budgets)..where((b) => b.id.equals(id))).go();

  // --------------------------------------------------------------- helpers

  static (DateTime, DateTime) _monthWindow(DateTime month) {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    return (start, end);
  }

  /// Live spent map keyed `categoryId:currencyCode` for the window.
  /// Grouping happens in Dart — personal ledgers are hundreds of rows per
  /// month, and the currency join keeps the SQL trivial and portable.
  Stream<Map<String, int>> _watchSpentByCategoryAndCurrency(
      DateTime start, DateTime end) {
    final query = _db.select(_db.transactions)
      ..where((t) => t.type.equalsValue(TransactionType.expense))
      ..where((t) => t.occurredAt.isBetweenValues(start, end));

    return query.watch().asyncMap((rows) async {
      final accounts = await _db.select(_db.accounts).get();
      final currencyOf = {for (final a in accounts) a.id: a.currencyCode};
      final map = <String, int>{};
      for (final t in rows) {
        final cur = currencyOf[t.accountId];
        if (t.categoryId == null || cur == null) continue;
        final key = '${t.categoryId}:$cur';
        map[key] = (map[key] ?? 0) + t.amountMinor;
      }
      return map;
    });
  }
}
