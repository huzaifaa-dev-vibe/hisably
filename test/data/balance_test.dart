import 'package:flutter_test/flutter_test.dart';
import 'package:hisably/core/db/app_database.dart';
import 'package:hisably/core/money/currency.dart';
import 'package:hisably/core/money/money.dart';
import 'package:hisably/core/money/money_formatter.dart';
import 'package:hisably/data/repositories/account_repository.dart';
import 'package:hisably/data/repositories/exceptions.dart';
import 'package:hisably/data/repositories/transaction_repository.dart';

/// Financial-correctness tests over a real in-memory SQLite database:
/// derived balances, P&L exclusions for transfers/exchanges, validations.
void main() {
  late AppDatabase db;
  late AccountRepository accounts;
  late TransactionRepository txs;
  late int cashId; // PKR cash, opening 100_000 (Rs 1,000.00)
  late int bankId; // PKR bank, opening 500_000 (Rs 5,000.00)
  late int usdId; // USD wallet, opening 0
  late int foodId;
  late int salaryId;

  setUp(() async {
    db = AppDatabase.memory();
    accounts = AccountRepository(db);
    txs = TransactionRepository(db);

    cashId = await accounts.createAccount(
      name: 'Cash',
      kind: AccountKind.cash,
      currencyCode: 'PKR',
      openingBalanceMinor: 100000,
      colorKey: 'teal',
    );
    bankId = await accounts.createAccount(
      name: 'Bank',
      kind: AccountKind.bank,
      currencyCode: 'PKR',
      openingBalanceMinor: 500000,
    );
    usdId = await accounts.createAccount(
      name: 'USD Wallet',
      kind: AccountKind.wallet,
      currencyCode: 'USD',
      openingBalanceMinor: 0,
    );

    final cats = await db.select(db.categories).get();
    foodId = cats.firstWhere((c) => c.name == 'Food').id;
    salaryId = cats.firstWhere((c) => c.name == 'Salary').id;
  });

  tearDown(() => db.close());

  group('system categories', () {
    test('seeded exactly once on create', () async {
      final cats = await db.select(db.categories).get();
      expect(cats.where((c) => c.direction == CategoryDirection.outflow).length,
          greaterThanOrEqualTo(10));
      expect(cats.where((c) => c.direction == CategoryDirection.inflow).length,
          greaterThanOrEqualTo(5));
    });
  });

  group('derived balances', () {
    test('opening balance is included', () async {
      final list = await accounts.watchAllWithBalances().first;
      expect(list.firstWhere((a) => a.account.id == cashId).balanceMinor, 100000);
      expect(list.firstWhere((a) => a.account.id == bankId).balanceMinor, 500000);
    });

    test('income adds, expense subtracts', () async {
      await txs.addIncome(accountId: cashId, amountMinor: 50000, categoryId: salaryId);
      await txs.addExpense(accountId: cashId, amountMinor: 20000, categoryId: foodId);
      final list = await accounts.watchAllWithBalances().first;
      expect(list.firstWhere((a) => a.account.id == cashId).balanceMinor, 130000);
    });

    test('transfer moves money without touching income/expense', () async {
      await txs.addTransfer(fromAccountId: cashId, toAccountId: bankId, amountMinor: 30000);

      final list = await accounts.watchAllWithBalances().first;
      expect(list.firstWhere((a) => a.account.id == cashId).balanceMinor, 70000);
      expect(list.firstWhere((a) => a.account.id == bankId).balanceMinor, 530000);

      // P&L must be zero for the month — a transfer is not income/expense.
      final totals = await txs.watchMonthlyTotals(DateTime.now()).first;
      final pkr = totals.firstWhere((t) => t.currencyCode == 'PKR');
      expect(pkr.incomeMinor, 0);
      expect(pkr.expenseMinor, 0);
    });

    test('exchange debits source (+fee) and credits destination', () async {
      // Rs 1,000 -> $3.50, fee Rs 25
      await txs.addExchange(
        fromAccountId: cashId,
        toAccountId: usdId,
        amountMinor: 100000,
        toAmountMinor: 350,
        feeMinor: 2500,
      );

      final list = await accounts.watchAllWithBalances().first;
      // 100000 + 2500 fee debited
      expect(list.firstWhere((a) => a.account.id == cashId).balanceMinor, -2500);
      expect(list.firstWhere((a) => a.account.id == usdId).balanceMinor, 350);

      // P&L unaffected by the exchange.
      final totals = await txs.watchMonthlyTotals(DateTime.now()).first;
      final pkr = totals.firstWhere((t) => t.currencyCode == 'PKR');
      expect(pkr.incomeMinor, 0);
      expect(pkr.expenseMinor, 0);
    });

    test('totals are grouped per currency, never summed across', () async {
      await txs.addIncome(accountId: cashId, amountMinor: 1000);
      await txs.addIncome(accountId: usdId, amountMinor: 500);
      final totals = await accounts.watchTotalsByCurrency().first;
      expect(totals['PKR'], 601000);
      expect(totals['USD'], 500);
    });

    test(
        'negative totals format without crashing '
        '(regression: home hero used Money.fromMinor, which throws on <0)',
        () async {
      // Drain both PKR accounts to zero with expenses (openings: 100000,
      // 500000), then let an exchange fee push the derived total negative.
      await txs.addExpense(accountId: cashId, amountMinor: 100000, categoryId: foodId);
      await txs.addExpense(accountId: bankId, amountMinor: 500000, categoryId: foodId);
      // Now cash = 0, bank = 0. An exchange debits amount + fee (2), making
      // the PKR total negative.
      await txs.addExchange(
        fromAccountId: cashId,
        toAccountId: usdId,
        amountMinor: 1,
        toAmountMinor: 1,
        feeMinor: 1, // cash balance becomes -2
      );

      final totals = await accounts.watchTotalsByCurrency().first;
      expect(totals['PKR'], -2);

      // The exact formatting call the home hero makes — must not throw.
      final c = CurrencyRegistry.byCode('PKR');
      expect(AmountFormat.money(Money.fromSigned(totals['PKR']!, c), includeCode: true),
          '-Rs 0.02 PKR');
    });
  });

  group('domain rules', () {
    test('rejects zero/negative amounts', () async {
      expect(
        () => txs.addExpense(accountId: cashId, amountMinor: 0, categoryId: foodId),
        throwsA(isA<DomainRuleException>()),
      );
      expect(
        () => txs.addIncome(accountId: cashId, amountMinor: -5),
        throwsA(isA<DomainRuleException>()),
      );
    });

    test('rejects transfer across currencies', () async {
      expect(
        () => txs.addTransfer(fromAccountId: cashId, toAccountId: usdId, amountMinor: 100),
        throwsA(isA<DomainRuleException>()),
      );
    });

    test('rejects transfer to the same account', () async {
      expect(
        () => txs.addTransfer(fromAccountId: cashId, toAccountId: cashId, amountMinor: 100),
        throwsA(isA<DomainRuleException>()),
      );
    });

    test('rejects category of wrong direction', () async {
      expect(
        () => txs.addExpense(accountId: cashId, amountMinor: 100, categoryId: salaryId),
        throwsA(isA<DomainRuleException>()),
      );
    });

    test('rejects fee above the exchanged amount', () async {
      expect(
        () => txs.addExchange(
              fromAccountId: cashId,
              toAccountId: usdId,
              amountMinor: 100,
              toAmountMinor: 1,
              feeMinor: 200,
            ),
        throwsA(isA<DomainRuleException>()),
      );
    });

    test('rejects invalid account creation', () async {
      expect(
        () => accounts.createAccount(
              name: 'X',
              kind: AccountKind.cash,
              currencyCode: 'TOOLONG',
              openingBalanceMinor: 0,
            ),
        throwsA(isA<DomainRuleException>()),
      );
      expect(
        () => accounts.createAccount(
              name: 'X',
              kind: AccountKind.cash,
              currencyCode: 'PKR',
              openingBalanceMinor: -1,
            ),
        throwsA(isA<DomainRuleException>()),
      );
    });
  });

  group('history filters', () {
    test('search matches note and category, type filter works', () async {
      await txs.addExpense(accountId: cashId, amountMinor: 500, categoryId: foodId, note: 'Lunch');
      await txs.addIncome(accountId: cashId, amountMinor: 9000, categoryId: salaryId);
      await txs.addTransfer(fromAccountId: cashId, toAccountId: bankId, amountMinor: 1000);

      final all = await txs
          .watchTransactions(const TxQueryFilter())
          .first;
      expect(all.length, 3);

      final byType = await txs.watchTransactions(const TxQueryFilter(type: TxTypeFilter.transfers)).first;
      expect(byType.length, 1);
      expect(byType.first.tx.type, TransactionType.transfer);

      final bySearch = await txs.watchTransactions(const TxQueryFilter(search: 'lunch')).first;
      expect(bySearch.length, 1);
      expect(bySearch.first.tx.note, 'Lunch');

      // bankId is a runtime value, so this filter cannot be const.
      final byAccount = await txs.watchTransactions(TxQueryFilter(accountId: bankId)).first;
      expect(byAccount.length, 1);
    });
  });

  group('undo / delete', () {
    test('deleted rows stop affecting balances', () async {
      final id = await txs.addExpense(accountId: cashId, amountMinor: 25000, categoryId: foodId);
      var list = await accounts.watchAllWithBalances().first;
      expect(list.firstWhere((a) => a.account.id == cashId).balanceMinor, 75000);

      await txs.deleteTransaction(id);
      list = await accounts.watchAllWithBalances().first;
      expect(list.firstWhere((a) => a.account.id == cashId).balanceMinor, 100000);
    });
  });

  group('archive', () {
    test('archived accounts leave the active list', () async {
      await accounts.archiveAccount(bankId);
      final archived = await (db.select(db.accounts)..where((a) => a.id.equals(bankId))).getSingle();
      expect(archived.archivedAt, isNotNull);
      final active = await accounts.watchAllActive().first;
      expect(active.where((a) => a.id == bankId), isEmpty);
    });
  });
}
