import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:hisably/core/db/app_database.dart';
import 'package:hisably/data/repositories/budget_repository.dart';
import 'package:hisably/data/repositories/transaction_repository.dart';

void main() {
  late AppDatabase db;
  late BudgetRepository budgets;
  late TransactionRepository txRepo;
  late Account cash;
  late Category food;
  late Category transport;

  setUp(() async {
    db = AppDatabase.memory();
    budgets = BudgetRepository(db);
    txRepo = TransactionRepository(db);
    final accountId = await db.into(db.accounts).insert(
          AccountsCompanion.insert(
            name: 'Cash',
            kind: AccountKind.cash,
            currencyCode: 'PKR',
            openingBalanceMinor: 100000,
          ),
        );
    cash = await (db.select(db.accounts)..where((a) => a.id.equals(accountId)))
        .getSingle();
    final foodId = await db.into(db.categories).insert(
          CategoriesCompanion.insert(
              name: 'Food', direction: CategoryDirection.outflow),
        );
    food = await (db.select(db.categories)..where((c) => c.id.equals(foodId)))
        .getSingle();
    final transportId = await db.into(db.categories).insert(
          CategoriesCompanion.insert(
              name: 'Transport', direction: CategoryDirection.outflow),
        );
    transport = await (db.select(db.categories)
          ..where((c) => c.id.equals(transportId)))
        .getSingle();
  });

  tearDown(() => db.close());

  test('setLimit inserts then updates (unique per category+currency)',
      () async {
    await budgets.setLimit(
        categoryId: food.id, currencyCode: 'PKR', monthlyLimitMinor: 10000);
    await budgets.setLimit(
        categoryId: food.id, currencyCode: 'PKR', monthlyLimitMinor: 20000);

    final rows = await db.select(db.budgets).get();
    expect(rows.length, 1);
    expect(rows.single.monthlyLimitMinor, 20000);
  });

  test('setLimit rejects zero/negative limits', () async {
    expect(
      () => budgets.setLimit(
          categoryId: food.id, currencyCode: 'PKR', monthlyLimitMinor: 0),
      throwsArgumentError,
    );
  });

  test('spent is derived from this month\'s expenses only', () async {
    await budgets.setLimit(
        categoryId: food.id, currencyCode: 'PKR', monthlyLimitMinor: 50000);
    final now = DateTime.now();

    await txRepo.addExpense(
        accountId: cash.id, amountMinor: 12000, categoryId: food.id);
    await txRepo.addExpense(
        accountId: cash.id, amountMinor: 8000, categoryId: food.id);
    // Other category and last month must not count.
    await txRepo.addExpense(
        accountId: cash.id, amountMinor: 999, categoryId: transport.id);
    await txRepo.addExpense(
        accountId: cash.id,
        amountMinor: 777,
        categoryId: food.id,
        occurredAt: DateTime(now.year, now.month - 1, 15));

    final list = await budgets.watchBudgetsWithSpent(now).first;
    expect(list.single.spentMinor, 20000);
    expect(list.single.limitMinor, 50000);
  });

  test('progress states: ok, warning (>=80%), over (>100%)', () async {
    await budgets.setLimit(
        categoryId: food.id, currencyCode: 'PKR', monthlyLimitMinor: 10000);
    final now = DateTime.now();
    await txRepo.addExpense(
        accountId: cash.id, amountMinor: 5000, categoryId: food.id);
    var list = await budgets.watchBudgetsWithSpent(now).first;
    expect(list.single.state, BudgetState.ok);
    expect(list.single.progress, closeTo(0.5, 0.0001));

    await txRepo.addExpense(
        accountId: cash.id, amountMinor: 3500, categoryId: food.id);
    list = await budgets.watchBudgetsWithSpent(now).first;
    expect(list.single.state, BudgetState.warning);

    await txRepo.addExpense(
        accountId: cash.id, amountMinor: 3000, categoryId: food.id);
    list = await budgets.watchBudgetsWithSpent(now).first;
    expect(list.single.state, BudgetState.over);
    expect(list.single.isOver, isTrue);
    expect(list.single.progress, 1.0);
  });

  test('delete removes the budget row', () async {
    await budgets.setLimit(
        categoryId: food.id, currencyCode: 'PKR', monthlyLimitMinor: 10000);
    final row = await db.select(db.budgets).getSingle();
    await budgets.delete(row.id);
    expect(await db.select(db.budgets).get(), isEmpty);
  });

  test('Value import works (drift companion write)', () async {
    // Guards the re-export in budget_repository stays valid.
    await budgets.setLimit(
        categoryId: food.id, currencyCode: 'PKR', monthlyLimitMinor: 100);
    final row = await db.select(db.budgets).getSingle();
    await (db.update(db.budgets)..where((b) => b.id.equals(row.id)))
        .write(BudgetsCompanion(monthlyLimitMinor: Value(150)));
    expect((await db.select(db.budgets).getSingle()).monthlyLimitMinor, 150);
  });
}
