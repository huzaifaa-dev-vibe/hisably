import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisably/core/db/app_database.dart';
import 'package:hisably/data/repositories/account_repository.dart';
import 'package:hisably/data/repositories/transaction_repository.dart';

/// Restart-recovery proof: data written to a file-backed database survives
/// closing and re-opening it — the same thing that happens between app
/// launches on a device.
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('hisably_test');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('transactions and accounts persist across close/reopen', () async {
    final path = '${tmp.path}/hisably.sqlite';

    // --- session 1
    final db1 = AppDatabase(NativeDatabase(File(path)));
    final accounts1 = AccountRepository(db1);
    final txs1 = TransactionRepository(db1);

    final accId = await accounts1.createAccount(
      name: 'Cash',
      kind: AccountKind.cash,
      currencyCode: 'PKR',
      openingBalanceMinor: 123456,
    );
    final cats = await db1.select(db1.categories).get();
    final food = cats.firstWhere((c) => c.name == 'Food');
    await txs1.addExpense(
      accountId: accId,
      amountMinor: 45600,
      categoryId: food.id,
      note: 'Groceries run',
    );
    await db1.close();

    // --- session 2 (simulated restart)
    final db2 = AppDatabase(NativeDatabase(File(path)));
    final accounts2 = AccountRepository(db2);

    final list = await accounts2.watchAllWithBalances().first;
    expect(list, hasLength(1));
    expect(list.first.account.name, 'Cash');
    // 123456 - 45600 = 77856
    expect(list.first.balanceMinor, 77856);

    final txList = await TransactionRepository(db2)
        .watchTransactions(const TxQueryFilter())
        .first;
    expect(txList, hasLength(1));
    expect(txList.first.tx.amountMinor, 45600);
    expect(txList.first.tx.note, 'Groceries run');
    expect(txList.first.category?.name, 'Food');

    await db2.close();
  });

  test('schema migration baseline: fresh v1 database opens cleanly', () async {
    final path = '${tmp.path}/fresh.sqlite';
    final db = AppDatabase(NativeDatabase(File(path)));
    // Touch the schema to force onCreate + beforeOpen.
    final accounts = await db.select(db.accounts).get();
    expect(accounts, isEmpty);
    final meta = await db.select(db.appMeta).get();
    expect(meta.map((m) => m.key), contains('seeded_at'));
    await db.close();

    // Reopen — migration strategy must be a no-op for the same version.
    final db2 = AppDatabase(NativeDatabase(File(path)));
    final again = await db2.select(db.accounts).get();
    expect(again, isEmpty);
    await db2.close();
  });
}
