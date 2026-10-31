import 'package:drift/drift.dart';

/// How an account holds money.
enum AccountKind { cash, bank, savings, wallet }

/// Which flow a category belongs to. (`in`/`out` are reserved words, hence
/// inflow/outflow.)
enum CategoryDirection { inflow, outflow }

/// The four financial event types.
///
/// Design decision — one row per event:
/// * income / expense affect the P&L of their account.
/// * transfer moves money between two accounts of the SAME currency; it is
///   never counted as income or expense (an expense is not a transfer).
/// * exchange converts money between two accounts of (potentially) different
///   currencies, preserving both original amounts verbatim; also never P&L.
///
/// Because each event is a single atomic row, transfers and exchanges cannot
/// be half-applied, and every balance is reproducible by aggregating rows.
enum TransactionType { income, expense, transfer, exchange }

/// Accounts the user owns: cash, bank, savings or digital wallet.
///
/// The opening balance is stored as a field (not as a synthetic transaction)
/// so the balance formula stays: opening + Σ(derived deltas of ledger rows).
@TableIndex(name: 'idx_accounts_currency', columns: {#currencyCode})
class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  TextColumn get kind => textEnum<AccountKind>()();
  TextColumn get currencyCode => text().withLength(min: 3, max: 3)();
  IntColumn get openingBalanceMinor => integer()();
  TextColumn get colorKey => text().withDefault(const Constant('blue'))();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get archivedAt => dateTime().nullable()();
}

/// Categories for income/expense classification.
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 40)();
  TextColumn get direction => textEnum<CategoryDirection>()();
  TextColumn get iconKey => text().withDefault(const Constant('category'))();
  IntColumn get sortOrder => integer().withDefault(const Constant(100))();
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();
}

/// The ledger. One row per financial event (see [TransactionType]).
///
/// Semantics of the amount columns:
/// * income/expense: [amountMinor] is in the source account's currency.
/// * transfer: [amountMinor] is debited from [accountId], [toAmountMinor]
///   (== amountMinor, enforced by repository) is credited to [toAccountId].
/// * exchange: (amountMinor + feeMinor) is debited from the source account,
///   [toAmountMinor] is credited to [toAccountId] in the destination
///   currency. Original amounts are preserved verbatim; the effective rate
///   is always *derived* (toAmount / amount), never stored as a float.
@TableIndex(name: 'idx_tx_occurred', columns: {#occurredAt})
@TableIndex(name: 'idx_tx_account', columns: {#accountId, #occurredAt})
@TableIndex(name: 'idx_tx_category', columns: {#categoryId})
@DataClassName('TransactionEntry')
class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get type => textEnum<TransactionType>()();
  IntColumn get accountId => integer().references(Accounts, #id)();
  IntColumn get toAccountId => integer().nullable().references(Accounts, #id)();
  IntColumn get amountMinor => integer()();
  IntColumn get toAmountMinor => integer().nullable()();
  IntColumn get feeMinor => integer().withDefault(const Constant(0))();
  IntColumn get categoryId => integer().nullable().references(Categories, #id)();
  TextColumn get note => text().nullable()();
  DateTimeColumn get occurredAt => dateTime()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// Reserved for the future recurrence engine (Phase 5). Never read yet.
  TextColumn get recurringRuleId => text().nullable()();
}

/// App-level settings that must be transactional with the ledger (reserved
/// for Phase 4/5: balance cache stamps, sync markers). UI preferences that
/// can be lost safely live in shared_preferences instead.
@DataClassName('AppMetaRow')
class AppMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Direction of a khata (personal ledger) entry.
///
/// `gave` = user handed money to the person (person owes user).
/// `took` = user received money from the person (user owes person).
/// Repayments are modelled as ordinary entries in the opposite direction,
/// so the running balance per person is Σ(gave) − Σ(took) per currency and
/// settlement needs no special-case rows.
enum KhataDirection { gave, took }

/// A monthly spending limit per category, in one specific currency.
///
/// Budgets are intentionally simple: one limit per (category, currency)
/// pair, applied to every month. Spent amount is always derived from the
/// ledger — never stored — so deleting a transaction instantly updates
/// progress.
@TableIndex(name: 'idx_budget_cat_cur', columns: {#categoryId, #currencyCode}, unique: true)
@DataClassName('BudgetRow')
class Budgets extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get categoryId => integer().references(Categories, #id)();
  TextColumn get currencyCode => text().withLength(min: 3, max: 3)();
  IntColumn get monthlyLimitMinor => integer()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// A person in the personal khata (digital ledger of informal debts).
@DataClassName('KhataPerson')
class KhataPeople extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  TextColumn get phone => text().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get colorKey => text().withDefault(const Constant('blue'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get archivedAt => dateTime().nullable()();
}

/// One khata movement: money given to or taken from a person.
/// Amounts live in the currency the hand-to-hand exchange happened in;
/// multi-currency people are supported by keeping balances per currency.
@TableIndex(name: 'idx_khata_person', columns: {#personId, #occurredAt})
@DataClassName('KhataEntry')
class KhataEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get personId => integer().references(KhataPeople, #id)();
  TextColumn get direction => textEnum<KhataDirection>()();
  IntColumn get amountMinor => integer()();
  TextColumn get currencyCode => text().withLength(min: 3, max: 3)();
  TextColumn get note => text().nullable()();
  DateTimeColumn get occurredAt => dateTime()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
