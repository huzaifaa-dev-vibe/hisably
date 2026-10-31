import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:hisably/core/db/app_database.dart';
import 'package:hisably/core/money/currency.dart';
import 'package:hisably/core/money/money.dart';
import 'package:hisably/core/money/money_formatter.dart';
import 'package:hisably/data/repositories/account_repository.dart';
import 'package:hisably/data/repositories/export_service.dart';
import 'package:hisably/data/repositories/khata_repository.dart';
import 'package:hisably/data/repositories/reports_repository.dart';
import 'package:hisably/data/repositories/transaction_repository.dart';

void main() {
  late AppDatabase db;
  late ReportsRepository reports;
  late TransactionRepository txRepo;
  late ExportService export;
  late Directory tempDir;
  late int cashId;
  late int bankId;
  late int usdWalletId;
  late int foodId;
  late int salaryId;

  setUp(() async {
    db = AppDatabase.memory();
    txRepo = TransactionRepository(db);
    reports = ReportsRepository(
      TransactionRepository(db),
      AccountRepository(db),
    );
    tempDir = await Directory.systemTemp.createTemp('hisably-test-exports');
    export = ExportService(db, exportDirFactory: () async => tempDir);
    cashId = await db.into(db.accounts).insert(AccountsCompanion.insert(
          name: 'Cash',
          kind: AccountKind.cash,
          currencyCode: 'PKR',
          openingBalanceMinor: 100000,
        ));
    bankId = await db.into(db.accounts).insert(AccountsCompanion.insert(
          name: 'Bank',
          kind: AccountKind.bank,
          currencyCode: 'PKR',
          openingBalanceMinor: 500000,
        ));
    usdWalletId = await db.into(db.accounts).insert(AccountsCompanion.insert(
          name: 'USD Wallet',
          kind: AccountKind.wallet,
          currencyCode: 'USD',
          openingBalanceMinor: 5000,
        ));
    foodId = await db.into(db.categories).insert(CategoriesCompanion.insert(
        name: 'Food', direction: CategoryDirection.outflow));
    salaryId = await db.into(db.categories).insert(CategoriesCompanion.insert(
        name: 'Salary', direction: CategoryDirection.inflow));
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test('category breakdown groups by category, scoped to one currency',
      () async {
    final now = DateTime.now();
    await txRepo.addExpense(
        accountId: cashId, amountMinor: 30000, categoryId: foodId);
    await txRepo.addExpense(
        accountId: bankId, amountMinor: 12000, categoryId: foodId);
    // USD expense must not leak into the PKR report.
    await txRepo.addExpense(
        accountId: usdWalletId, amountMinor: 9999, categoryId: foodId);

    final slices = await reports
        .watchCategoryBreakdown(
            month: now, currencyCode: 'PKR', expense: true)
        .first;
    expect(slices, hasLength(1));
    expect(slices.single.name, 'Food');
    expect(slices.single.totalMinor, 42000);
  });

  test('daily flow: one point per day of the month, in/out separated',
      () async {
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    await txRepo.addExpense(
        accountId: cashId,
        amountMinor: 5000,
        categoryId: foodId,
        occurredAt: DateTime(now.year, now.month, 3, 14));
    await txRepo.addIncome(
        accountId: bankId,
        amountMinor: 100000,
        categoryId: salaryId,
        occurredAt: DateTime(now.year, now.month, 3, 10));

    final flow =
        await reports.watchDailyFlow(month: now, currencyCode: 'PKR').first;
    expect(flow, hasLength(daysInMonth));
    expect(flow[2].inMinor, 100000);
    expect(flow[2].outMinor, 5000);
    expect(flow[0].inMinor, 0);
    // Transfers never count as P&L.
    await txRepo.addTransfer(
        fromAccountId: bankId,
        toAccountId: cashId,
        amountMinor: 25000,
        occurredAt: DateTime(now.year, now.month, 5));
    final flow2 =
        await reports.watchDailyFlow(month: now, currencyCode: 'PKR').first;
    expect(flow2[4].inMinor, 0);
    expect(flow2[4].outMinor, 0);
  });

  test('monthly flow aggregates the last N months', () async {
    final now = DateTime.now();
    await txRepo.addExpense(
        accountId: cashId,
        amountMinor: 8000,
        categoryId: foodId,
        occurredAt: DateTime(now.year, now.month - 2, 10));
    await txRepo.addIncome(
        accountId: bankId,
        amountMinor: 200000,
        categoryId: salaryId,
        occurredAt: DateTime(now.year, now.month, 2));

    final series =
        await reports.watchMonthlyFlow(currencyCode: 'PKR', months: 6).first;
    expect(series, hasLength(6));
    expect(series.last.inMinor, 200000); // current month
    expect(series[3].outMinor, 8000); // two months back (index 6-1-2)
    expect(series.last.outMinor, 0);
  });

  test('balance series walks from the derived total and lands on it',
      () async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Total before: PKR 6000.00. Spend 1,500.00 today, exchange 2,000.00
    // PKR→USD with 100.00 fee (the USD leg does not affect the PKR series).
    await txRepo.addExpense(
        accountId: cashId,
        amountMinor: 150000,
        categoryId: foodId,
        occurredAt: today);
    await txRepo.addExchange(
        fromAccountId: bankId,
        toAccountId: usdWalletId,
        amountMinor: 200000,
        toAmountMinor: 1000,
        feeMinor: 10000,
        occurredAt: today);

    final totals = await AccountRepository(db).watchTotalsByCurrency().first;
    final points =
        await reports.watchBalanceSeries(currencyCode: 'PKR', days: 30).first;

    expect(points, hasLength(30));
    final currentPkr = totals['PKR']!;
    expect(currentPkr, 600000 - 150000 - 200000 - 10000);
    // The last point equals the derived total — internal consistency.
    expect(points.last.balanceMinor, currentPkr);
    // Nothing happened before today, so all earlier points equal opening.
    final opening = points.first.balanceMinor;
    for (final p in points.take(29)) {
      expect(p.balanceMinor, opening);
    }
    expect(points.last.balanceMinor, opening - 360000);
  });

  test('balance series consistency after income+expense', () async {
    await txRepo.addExpense(accountId: cashId, amountMinor: 12345, categoryId: foodId);
    await txRepo.addIncome(accountId: bankId, amountMinor: 6789, categoryId: salaryId);
    final totals = await AccountRepository(db).watchTotalsByCurrency().first;
    final points =
        await reports.watchBalanceSeries(currencyCode: 'PKR', days: 14).first;
    expect(points, hasLength(14));
    expect(points.last.balanceMinor, totals['PKR']);
  });

  // ------------------------------------------------------------ CSV export

  test('CSV export escapes notes and includes every transaction', () async {
    await txRepo.addExpense(
        accountId: cashId,
        amountMinor: 500,
        categoryId: foodId,
        note: 'lunch, "special" one');
    final result = await export.exportTransactionsCsv();
    expect(result.summary, contains('1 transactions'));
    final csv = await File(result.path).readAsString();
    expect(csv, startsWith('id,type,date,account'));
    expect(csv, contains('"lunch, ""special"" one"'));
  });

  // ------------------------------------------------------------- backup

  test('backup → restore roundtrip reproduces the ledger exactly', () async {
    final now = DateTime.now();
    // Unique names: the memory DB also seeds the default category set, so
    // 'Food' would be ambiguous when matching after restore.
    final snackId = await db.into(db.categories).insert(
        CategoriesCompanion.insert(
            name: 'Snacks', direction: CategoryDirection.outflow));
    await txRepo.addExpense(
        accountId: cashId,
        amountMinor: 700,
        categoryId: snackId,
        note: 'chai',
        occurredAt: now);
    await txRepo.addTransfer(
        fromAccountId: cashId, toAccountId: bankId, amountMinor: 10000);

    // Khata data goes through the real repository.
    final khata = KhataRepository(db);
    final personId = await khata.addPerson(name: 'Sara', note: 'neighbour');
    await khata.addEntry(
      personId: personId,
      direction: KhataDirection.gave,
      amountMinor: 1234,
      currencyCode: 'PKR',
      note: 'helped with rent',
    );

    await db.into(db.budgets).insert(BudgetsCompanion.insert(
          categoryId: snackId,
          currencyCode: 'PKR',
          monthlyLimitMinor: 25000,
        ));

    final backup = await export.backup();
    final backupPath = backup.path;
    expect(backup.summary, contains('2 transactions'));

    // Destroy a row, then restore from the file.
    await (db.delete(db.transactions)..where((t) => t.id.equals(1))).go();
    expect(await db.select(db.transactions).get(), hasLength(1));

    await export.restoreFromJsonFile(backupPath);

    final txs = await db.select(db.transactions).get();
    expect(txs, hasLength(2));
    final expense = txs.firstWhere((t) => t.type == TransactionType.expense);
    expect(expense.note, 'chai');
    expect(expense.amountMinor, 700);
    // Categories were re-inserted with new ids but same names.
    final cats = await db.select(db.categories).get();
    expect(cats.map((c) => c.name), containsAll(['Snacks', 'Food', 'Salary']));
    // Budgets reference the REMAPPED category id.
    final snackCats = cats.where((c) => c.name == 'Snacks').toList();
    expect(snackCats, hasLength(1));
    final budgets = await db.select(db.budgets).get();
    expect(budgets.single.categoryId, snackCats.single.id);
    // Khata restored with remapped person ids.
    final people = await db.select(db.khataPeople).get();
    expect(people.single.name, 'Sara');
    final entries = await db.select(db.khataEntries).get();
    expect(entries.single.personId, people.single.id);
    expect(entries.single.amountMinor, 1234);
    // Money formatting still exact (integer minor units preserved).
    final c = CurrencyRegistry.byCode('PKR');
    expect(AmountFormat.money(Money.fromMinor(expense.amountMinor, c)),
        contains('7.00'));
  });

  test('restore rejects malformed payloads without touching data', () async {
    await txRepo.addExpense(accountId: cashId, amountMinor: 100);
    final before = await db.select(db.transactions).get();

    final bad = File('${tempDir.path}/bad.json');
    await bad.writeAsString('{"app": "other-app", "backup_version": 1}');

    await expectLater(
      export.restoreFromJsonFile(bad.path),
      throwsFormatException,
    );
    // Data untouched.
    expect((await db.select(db.transactions).get()).length, before.length);
  });

  test('Value import usable for budget edits (drift companion)', () async {
    await db.into(db.budgets).insert(BudgetsCompanion.insert(
          categoryId: foodId,
          currencyCode: 'PKR',
          monthlyLimitMinor: 25000,
        ));
    final row = await db.select(db.budgets).getSingle();
    await (db.update(db.budgets)..where((b) => b.id.equals(row.id)))
        .write(BudgetsCompanion(monthlyLimitMinor: Value(30000)));
    expect((await db.select(db.budgets).getSingle()).monthlyLimitMinor, 30000);
  });
}
