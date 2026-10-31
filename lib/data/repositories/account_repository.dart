import 'package:drift/drift.dart';

import '../../core/db/app_database.dart';
import '../../core/money/currency.dart';
import 'exceptions.dart';

/// A derived, reproducible account balance.
///
/// balance = opening + Σ(income) − Σ(expense) − Σ(transferOut + exchangeOut
/// incl. fees) + Σ(transferIn + exchangeIn). Every term comes from ledger
/// rows, so the number is always reproducible from the underlying records.
class AccountWithBalance {
  const AccountWithBalance({required this.account, required this.balanceMinor});

  final Account account;
  final int balanceMinor;

  Currency get currency => CurrencyRegistry.byCode(account.currencyCode);
}

/// Read/write access to accounts and derived balances.
class AccountRepository {
  AccountRepository(this._db);

  final AppDatabase _db;

  /// All active accounts with their live, derived balances.
  Stream<List<AccountWithBalance>> watchAllWithBalances() {
    final q = _db.customSelect(
      '''
      SELECT a.id AS account_id,
             a.opening_balance_minor
             + COALESCE((SELECT SUM(CASE
                   WHEN t.type = 'income' THEN t.amount_minor
                   WHEN t.type = 'expense' THEN -t.amount_minor
                   WHEN t.type IN ('transfer', 'exchange')
                       THEN -(t.amount_minor + t.fee_minor)
                   ELSE 0
                 END)
               FROM transactions t WHERE t.account_id = a.id), 0)
             + COALESCE((SELECT SUM(t.to_amount_minor)
               FROM transactions t WHERE t.to_account_id = a.id), 0)
             AS balance_minor
      FROM accounts a
      WHERE a.archived_at IS NULL
      ORDER BY a.created_at ASC, a.id ASC
      ''',
      readsFrom: {_db.accounts, _db.transactions},
    );
    return q.watch().asyncMap((rows) async {
      final balances = {
        for (final r in rows) r.data['account_id'] as int: r.data['balance_minor'] as int,
      };
      final accounts = await (_db.select(_db.accounts)
            ..where((a) => a.archivedAt.isNull())
            ..orderBy([(a) => OrderingTerm.asc(a.createdAt)]))
          .get();
      return [
        for (final a in accounts)
          AccountWithBalance(account: a, balanceMinor: balances[a.id] ?? a.openingBalanceMinor),
      ];
    });
  }

  /// Totals grouped per currency — never mixes currencies into one number.
  Stream<Map<String, int>> watchTotalsByCurrency() {
    return watchAllWithBalances().map((list) {
      final totals = <String, int>{};
      for (final a in list) {
        final code = a.account.currencyCode;
        totals[code] = (totals[code] ?? 0) + a.balanceMinor;
      }
      return totals;
    });
  }

  Stream<Account?> watchAccount(int id) {
    return (_db.select(_db.accounts)..where((a) => a.id.equals(id)))
        .watchSingleOrNull();
  }

  Future<Account?> getAccount(int id) =>
      (_db.select(_db.accounts)..where((a) => a.id.equals(id))).getSingleOrNull();

  Future<List<Account>> accountsOfCurrency(String code) {
    return (_db.select(_db.accounts)
          ..where((a) => a.currencyCode.equals(code.toUpperCase()) & a.archivedAt.isNull())
          ..orderBy([(a) => OrderingTerm.asc(a.name)]))
        .get();
  }

  Stream<List<Account>> watchAccountsOfCurrency(String code) {
    return (_db.select(_db.accounts)
          ..where((a) => a.currencyCode.equals(code.toUpperCase()) & a.archivedAt.isNull())
          ..orderBy([(a) => OrderingTerm.asc(a.name)]))
        .watch();
  }

  Stream<List<Account>> watchAllActive() {
    return (_db.select(_db.accounts)
          ..where((a) => a.archivedAt.isNull())
          ..orderBy([(a) => OrderingTerm.asc(a.createdAt)]))
        .watch();
  }

  /// Creates an account and returns its id.
  ///
  /// The opening balance is stored on the row itself (see tables.dart) —
  /// deliberately NOT a synthetic transaction, keeping the balance formula
  /// trivially reproducible.
  Future<int> createAccount({
    required String name,
    required AccountKind kind,
    required String currencyCode,
    required int openingBalanceMinor,
    String colorKey = 'blue',
    String? note,
  }) {
    final code = currencyCode.toUpperCase();
    if (!CurrencyRegistry.isValidCode(code)) {
      throw DomainRuleException(DomainRule.currencyMismatch, 'invalid code $code');
    }
    if (openingBalanceMinor < 0 ||
        openingBalanceMinor > 9999999999999) {
      throw DomainRuleException(DomainRule.amountMustBePositive, 'opening balance');
    }
    return _db.into(_db.accounts).insert(AccountsCompanion.insert(
          name: name.trim(),
          kind: kind,
          currencyCode: code,
          openingBalanceMinor: openingBalanceMinor,
          colorKey: Value(colorKey),
          note: Value(note),
        ));
  }

  Future<void> archiveAccount(int id) {
    return (_db.update(_db.accounts)..where((a) => a.id.equals(id)))
        .write(AccountsCompanion(archivedAt: Value(DateTime.now())));
  }
}
