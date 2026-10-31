import 'package:drift/drift.dart';

import '../../core/db/app_database.dart';
import '../../core/money/currency.dart';
import 'exceptions.dart';

/// A ledger row enriched with the display names it needs.
class TxWithRefs {
  const TxWithRefs({
    required this.tx,
    required this.account,
    required this.toAccount,
    required this.category,
  });

  final TransactionEntry tx;
  final Account? account;
  final Account? toAccount;
  final Category? category;

  /// Currency of the primary (source) leg.
  Currency get currency => CurrencyRegistry.byCode(account?.currencyCode ?? 'XXX');
}

enum TxTypeFilter { all, income, expense, transfers }

class TxQueryFilter {
  const TxQueryFilter({
    this.type = TxTypeFilter.all,
    this.accountId,
    this.search,
    this.from,
    this.to,
    this.limit = 500,
  });

  final TxTypeFilter type;
  final int? accountId;
  final String? search;
  final DateTime? from;
  final DateTime? to;
  final int limit;

  TxQueryFilter copyWith({
    TxTypeFilter? type,
    int? accountId,
    bool clearAccount = false,
    String? search,
    bool clearSearch = false,
    DateTime? from,
    DateTime? to,
    int? limit,
  }) {
    return TxQueryFilter(
      type: type ?? this.type,
      accountId: clearAccount ? null : (accountId ?? this.accountId),
      search: clearSearch ? null : (search ?? this.search),
      from: from ?? this.from,
      to: to ?? this.to,
      limit: limit ?? this.limit,
    );
  }
}

/// The ledger repository — every money-mutating operation lives here so
/// validation and atomicity are enforced in exactly one place.
class TransactionRepository {
  TransactionRepository(this._db);

  final AppDatabase _db;

  // ---------------------------------------------------------------- watch

  Stream<List<TxWithRefs>> watchTransactions(TxQueryFilter f) {
    final toAcc = _db.alias(_db.accounts, 'to_acc');
    final query = _db.select(_db.transactions).join([
      leftOuterJoin(_db.accounts, _db.accounts.id.equalsExp(_db.transactions.accountId)),
      leftOuterJoin(toAcc, toAcc.id.equalsExp(_db.transactions.toAccountId)),
      leftOuterJoin(_db.categories, _db.categories.id.equalsExp(_db.transactions.categoryId)),
    ]);

    final t = _db.transactions;
    Expression<bool> where = const Constant(true);

    switch (f.type) {
      case TxTypeFilter.all:
        break;
      case TxTypeFilter.income:
        where = where & t.type.equals(TransactionType.income.name);
      case TxTypeFilter.expense:
        where = where & t.type.equals(TransactionType.expense.name);
      case TxTypeFilter.transfers:
        where = where & t.type.isIn([TransactionType.transfer.name, TransactionType.exchange.name]);
    }
    if (f.accountId != null) {
      where = where & (t.accountId.equals(f.accountId!) | t.toAccountId.equals(f.accountId!));
    }
    if (f.search != null && f.search!.trim().isNotEmpty) {
      final needle = '%${f.search!.trim()}%';
      where = where & (t.note.like(needle) | _db.categories.name.like(needle));
    }
    if (f.from != null) {
      where = where & t.occurredAt.isBiggerOrEqualValue(f.from!);
    }
    if (f.to != null) {
      where = where & t.occurredAt.isSmallerOrEqualValue(f.to!);
    }

    query.where(where);
    query.orderBy([OrderingTerm.desc(_db.transactions.occurredAt), OrderingTerm.desc(_db.transactions.id)]);
    query.limit(f.limit);

    return query.watch().map((rows) {
      return rows.map((row) {
        return TxWithRefs(
          tx: row.readTable(_db.transactions),
          account: row.readTableOrNull(_db.accounts),
          toAccount: row.readTableOrNull(toAcc),
          category: row.readTableOrNull(_db.categories),
        );
      }).toList();
    });
  }

  // --------------------------------------------------------------- income

  Future<int> addIncome({
    required int accountId,
    required int amountMinor,
    int? categoryId,
    String? note,
    DateTime? occurredAt,
  }) =>
      _addInOrOut(
        type: TransactionType.income,
        accountId: accountId,
        amountMinor: amountMinor,
        categoryId: categoryId,
        note: note,
        occurredAt: occurredAt,
      );

  Future<int> addExpense({
    required int accountId,
    required int amountMinor,
    int? categoryId,
    String? note,
    DateTime? occurredAt,
  }) =>
      _addInOrOut(
        type: TransactionType.expense,
        accountId: accountId,
        amountMinor: amountMinor,
        categoryId: categoryId,
        note: note,
        occurredAt: occurredAt,
      );

  Future<int> _addInOrOut({
    required TransactionType type,
    required int accountId,
    required int amountMinor,
    required int? categoryId,
    required String? note,
    required DateTime? occurredAt,
  }) {
    assert(type == TransactionType.income || type == TransactionType.expense);
    return _db.transaction(() async {
      await _requireAccount(accountId);
      if (amountMinor <= 0) {
        throw DomainRuleException(DomainRule.amountMustBePositive);
      }
      if (categoryId != null) {
        final cat = await (_db.select(_db.categories)..where((c) => c.id.equals(categoryId)))
            .getSingleOrNull();
        if (cat == null) {
          throw DomainRuleException(DomainRule.categoryNotFound);
        }
        final expected = type == TransactionType.income
            ? CategoryDirection.inflow
            : CategoryDirection.outflow;
        if (cat.direction != expected) {
          throw DomainRuleException(DomainRule.categoryDirectionMismatch);
        }
      }
      return _db.into(_db.transactions).insert(TransactionsCompanion.insert(
            type: type,
            accountId: accountId,
            amountMinor: amountMinor,
            categoryId: Value(categoryId),
            note: Value(note?.trim().isEmpty ?? true ? null : note!.trim()),
            occurredAt: occurredAt ?? DateTime.now(),
          ));
    });
  }

  // ------------------------------------------------------------- transfer

  /// Moves money between two accounts of the SAME currency. A transfer is a
  /// single atomic ledger row and never counts as income or expense.
  Future<int> addTransfer({
    required int fromAccountId,
    required int toAccountId,
    required int amountMinor,
    String? note,
    DateTime? occurredAt,
  }) {
    return _db.transaction(() async {
      if (amountMinor <= 0) {
        throw DomainRuleException(DomainRule.amountMustBePositive);
      }
      if (fromAccountId == toAccountId) {
        throw DomainRuleException(DomainRule.sameAccount);
      }
      final from = await _requireAccount(fromAccountId);
      final to = await _requireAccount(toAccountId);
      if (from.currencyCode != to.currencyCode) {
        // Cross-currency movement must go through Currency Exchange so both
        // original amounts are preserved explicitly.
        throw DomainRuleException(DomainRule.currencyMismatch,
            'use exchange for ${from.currencyCode}→${to.currencyCode}');
      }
      return _db.into(_db.transactions).insert(TransactionsCompanion.insert(
            type: TransactionType.transfer,
            accountId: fromAccountId,
            toAccountId: Value(toAccountId),
            amountMinor: amountMinor,
            toAmountMinor: Value(amountMinor),
            note: Value(note?.trim().isEmpty ?? true ? null : note!.trim()),
            occurredAt: occurredAt ?? DateTime.now(),
          ));
    });
  }

  // ------------------------------------------------------------- exchange

  /// Manual currency exchange between two accounts.
  ///
  /// * source debit = [amountMinor] + [feeMinor] (fee in source currency)
  /// * destination credit = [toAmountMinor] (destination currency)
  /// * both original amounts are stored verbatim; the effective rate is
  ///   derived on read as toAmountMinor / amountMinor — never stored, never
  ///   a float.
  Future<int> addExchange({
    required int fromAccountId,
    required int toAccountId,
    required int amountMinor,
    required int toAmountMinor,
    int feeMinor = 0,
    String? note,
    DateTime? occurredAt,
  }) {
    return _db.transaction(() async {
      if (amountMinor <= 0 || toAmountMinor <= 0) {
        throw DomainRuleException(DomainRule.amountMustBePositive);
      }
      if (fromAccountId == toAccountId) {
        throw DomainRuleException(DomainRule.sameAccount);
      }
      await _requireAccount(fromAccountId);
      await _requireAccount(toAccountId);
      if (feeMinor < 0 || feeMinor > amountMinor) {
        throw DomainRuleException(DomainRule.feeOutOfRange);
      }
      return _db.into(_db.transactions).insert(TransactionsCompanion.insert(
            type: TransactionType.exchange,
            accountId: fromAccountId,
            toAccountId: Value(toAccountId),
            amountMinor: amountMinor,
            toAmountMinor: Value(toAmountMinor),
            feeMinor: Value(feeMinor),
            note: Value(note?.trim().isEmpty ?? true ? null : note!.trim()),
            occurredAt: occurredAt ?? DateTime.now(),
          ));
    });
  }

  // ---------------------------------------------------------------- undo

  /// Deletes a ledger row (used by the Quick Add undo affordance and future
  /// history editing). Balances re-derive automatically on next stream read.
  Future<void> deleteTransaction(int id) {
    return _db.transaction(() async {
      final deleted = await (_db.delete(_db.transactions)..where((t) => t.id.equals(id))).go();
      if (deleted == 0) {
        throw StateError('transaction $id does not exist');
      }
    });
  }

  // ------------------------------------------------------------- summaries

  /// Monthly income/expense totals grouped per currency (never summed
  /// across currencies). [month] is any instant inside the month.
  Stream<List<MonthlyTotals>> watchMonthlyTotals(DateTime month) {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    final q = _db.customSelect(
      '''
      SELECT a.currency_code AS code,
             COALESCE(SUM(CASE WHEN t.type = 'income' THEN t.amount_minor ELSE 0 END), 0) AS income_minor,
             COALESCE(SUM(CASE WHEN t.type = 'expense' THEN t.amount_minor ELSE 0 END), 0) AS expense_minor
      FROM transactions t
      JOIN accounts a ON a.id = t.account_id
      WHERE t.occurred_at >= ? AND t.occurred_at < ?
      GROUP BY a.currency_code
      ''',
      variables: [Variable(start.millisecondsSinceEpoch ~/ 1000), Variable(end.millisecondsSinceEpoch ~/ 1000)],
      readsFrom: {_db.transactions, _db.accounts},
    );
    return q.watch().map((rows) => [
          for (final r in rows)
            MonthlyTotals(
              currencyCode: r.data['code'] as String,
              incomeMinor: r.data['income_minor'] as int,
              expenseMinor: r.data['expense_minor'] as int,
            ),
        ]);
  }

  Future<Account> _requireAccount(int id) async {
    final a = await (_db.select(_db.accounts)..where((x) => x.id.equals(id))).getSingleOrNull();
    if (a == null) throw DomainRuleException(DomainRule.accountNotFound);
    return a;
  }
}

class MonthlyTotals {
  const MonthlyTotals({
    required this.currencyCode,
    required this.incomeMinor,
    required this.expenseMinor,
  });

  final String currencyCode;
  final int incomeMinor;
  final int expenseMinor;
}
