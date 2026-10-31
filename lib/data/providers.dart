import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/db/app_database.dart';
import '../core/money/currency.dart';
import 'repositories/account_repository.dart';
import 'repositories/budget_repository.dart';
import 'repositories/export_service.dart';
import 'repositories/khata_repository.dart';
import 'repositories/reports_repository.dart';
import 'repositories/transaction_repository.dart';

// Re-export repository result types so feature code gets every model from
// one import.
export 'repositories/account_repository.dart';
export 'repositories/budget_repository.dart';
export 'repositories/export_service.dart';
export 'repositories/khata_repository.dart';
export 'repositories/reports_repository.dart';
export 'repositories/transaction_repository.dart';

/// SharedPreferences — overridden in main() with the real instance and in
/// tests with mock values.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('overridden in bootstrap'),
);

/// The single SQLite database. Overridden with an in-memory instance in
/// tests; opened by `bootstrap()` in production.
final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('overridden in bootstrap'),
);

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => AccountRepository(ref.watch(appDatabaseProvider)),
);

final transactionRepositoryProvider = Provider<TransactionRepository>(
  (ref) => TransactionRepository(ref.watch(appDatabaseProvider)),
);

final budgetRepositoryProvider = Provider<BudgetRepository>(
  (ref) => BudgetRepository(ref.watch(appDatabaseProvider)),
);

final khataRepositoryProvider = Provider<KhataRepository>(
  (ref) => KhataRepository(ref.watch(appDatabaseProvider)),
);

final reportsRepositoryProvider = Provider<ReportsRepository>(
  (ref) => ReportsRepository(
    ref.watch(transactionRepositoryProvider),
    ref.watch(accountRepositoryProvider),
  ),
);

final exportServiceProvider = Provider<ExportService>(
  (ref) => ExportService(ref.watch(appDatabaseProvider)),
);

/// Budgets with live derived spend for the month of [month].
final budgetsWithSpentProvider =
    StreamProvider.family<List<BudgetWithSpent>, DateTime>((ref, month) {
  return ref.watch(budgetRepositoryProvider).watchBudgetsWithSpent(month);
});

/// Khata people with derived per-currency net balances.
final khataPeopleProvider = StreamProvider<List<PersonWithBalance>>(
  (ref) => ref.watch(khataRepositoryProvider).watchPeopleWithBalances(),
);

/// Entries of one khata person.
final khataEntriesProvider =
    StreamProvider.family<List<KhataEntry>, int>((ref, personId) {
  return ref.watch(khataRepositoryProvider).watchEntries(personId);
});

/// One khata person.
final khataPersonProvider =
    StreamProvider.family<KhataPerson?, int>((ref, id) {
  return ref.watch(khataRepositoryProvider).watchPerson(id);
});

// ---- report series (all per-currency; charts never mix currencies) ------

final categoryBreakdownProvider = StreamProvider.family<List<CategorySlice>,
    ({DateTime month, String currency, bool expense})>((ref, params) {
  return ref.watch(reportsRepositoryProvider).watchCategoryBreakdown(
        month: params.month,
        currencyCode: params.currency,
        expense: params.expense,
      );
});

final dailyFlowProvider =
    StreamProvider.family<List<DailyFlowPoint>, ({DateTime month, String currency})>(
        (ref, params) {
  return ref
      .watch(reportsRepositoryProvider)
      .watchDailyFlow(month: params.month, currencyCode: params.currency);
});

final monthlyFlowProvider =
    StreamProvider.family<List<MonthlyFlowPoint>, String>((ref, currency) {
  return ref.watch(reportsRepositoryProvider).watchMonthlyFlow(currencyCode: currency);
});

final balanceSeriesProvider =
    StreamProvider.family<List<BalancePoint>, String>((ref, currency) {
  return ref.watch(reportsRepositoryProvider).watchBalanceSeries(currencyCode: currency);
});

/// Active accounts with derived balances (the single source of truth for
/// every balance shown in the app).
final accountsWithBalancesProvider = StreamProvider<List<AccountWithBalance>>(
  (ref) => ref.watch(accountRepositoryProvider).watchAllWithBalances(),
);

/// Totals grouped per currency — the home hero never mixes currencies.
final totalsByCurrencyProvider = StreamProvider<Map<String, int>>(
  (ref) => ref.watch(accountRepositoryProvider).watchTotalsByCurrency(),
);

/// Monthly in/out per currency for the month containing [month].
final monthlyTotalsProvider =
    StreamProvider.family<List<MonthlyTotals>, DateTime>((ref, month) {
  return ref.watch(transactionRepositoryProvider).watchMonthlyTotals(month);
});

/// The most recent ledger rows (home dashboard teaser).
final recentTransactionsProvider = StreamProvider<List<TxWithRefs>>((ref) {
  return ref
      .watch(transactionRepositoryProvider)
      .watchTransactions(const TxQueryFilter(limit: 8));
});

/// Single account stream (account details screen).
final accountDetailsProvider =
    StreamProvider.family<Account?, int>((ref, id) {
  return ref.watch(accountRepositoryProvider).watchAccount(id);
});

/// Parameterised ledger query (account details, history filters).
final accountTransactionsProvider = StreamProvider.family<List<TxWithRefs>,
    TxQueryFilter>((ref, filter) {
  return ref.watch(transactionRepositoryProvider).watchTransactions(filter);
});

/// All active accounts (no balances).
final accountsProvider = StreamProvider<List<Account>>(
  (ref) => ref.watch(accountRepositoryProvider).watchAllActive(),
);

/// Categories ordered for pickers.
final categoriesProvider = StreamProvider<List<Category>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.categories)
        ..orderBy([(c) => OrderingTerm.asc(c.sortOrder), (c) => OrderingTerm.asc(c.id)]))
      .watch();
});

/// The currency Quick Add assumes on open. Default PKR; user-changeable in
/// Settings (Phase 5) and per-session in the Quick Add top bar.
final primaryCurrencyProvider =
    NotifierProvider<PrimaryCurrency, String>(PrimaryCurrency.new);

class PrimaryCurrency extends Notifier<String> {
  static const _key = 'primary_currency';

  @override
  String build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final saved = prefs.getString(_key);
    return saved != null && CurrencyRegistry.isValidCode(saved)
        ? saved
        : CurrencyRegistry.pkr.code;
  }

  Future<void> set(String code) async {
    if (!CurrencyRegistry.isValidCode(code)) return;
    state = code.toUpperCase();
    await ref.read(sharedPreferencesProvider).setString(_key, state);
  }
}

/// Whether Quick Add should skip the details step when sensible defaults
/// exist (spec: "Allow users to configure whether a transaction saves
/// immediately or opens the details step"). Default: show details.
final quickSaveImmediatelyProvider =
    NotifierProvider<QuickSaveImmediately, bool>(QuickSaveImmediately.new);

class QuickSaveImmediately extends Notifier<bool> {
  static const _key = 'quick_save_immediately';

  @override
  bool build() {
    return ref.watch(sharedPreferencesProvider).getBool(_key) ?? false;
  }

  Future<void> set(bool value) async {
    state = value;
    await ref.read(sharedPreferencesProvider).setBool(_key, value);
  }
}
