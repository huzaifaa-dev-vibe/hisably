import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/money/currency.dart';
import '../../core/money/money.dart';
import '../../core/money/money_formatter.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/aurora_background.dart';
import '../../core/theme/glass.dart';
import '../../core/theme/theme_spec.dart';
import '../../data/providers.dart';
import '../quick_add/transaction_row.dart';

/// Single account: hero balance, this-month flow for the account, and the
/// account's ledger.
class AccountDetailsScreen extends ConsumerWidget {
  const AccountDetailsScreen({super.key, required this.accountId});

  final int accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountAsync = ref.watch(accountDetailsProvider(accountId));
    final txAsync = ref.watch(
      accountTransactionsProvider(
        TxQueryFilter(accountId: accountId, limit: 200),
      ),
    );

    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(backgroundColor: Colors.transparent, title: const Text('Account')),
        body: SafeArea(
          bottom: false,
          child: accountAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Could not load account.', style: Theme.of(context).textTheme.bodyMedium)),
            data: (account) {
              if (account == null) {
                return Center(
                  child: Text('This account no longer exists.',
                      style: Theme.of(context).textTheme.bodyMedium),
                );
              }
              final currency = CurrencyRegistry.byCode(account.currencyCode);
              final balances = ref.watch(accountsWithBalancesProvider).value;
              final ab = balances?.where((x) => x.account.id == accountId).firstOrNull;
              final balanceMinor = ab?.balanceMinor ?? account.openingBalanceMinor;

              return ListView(
                padding: AppDimens.pagePadding,
                children: [
                  const SizedBox(height: 6),
                  GlassPanel(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(account.name, style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 4),
                        Text(
                          '${currency.code} · ${_kindLabel(account.kind)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          AmountFormat.money(Money.fromSigned(balanceMinor, currency),
                              includeCode: true),
                          style: Theme.of(context)
                              .textTheme
                              .displaySmall!
                              .copyWith(
                                fontFeatures: [FontFeature.tabularFigures()],
                                color: balanceMinor < 0 ? context.expenseColor : null,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('History', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 10),
                  txAsync.when(
                    loading: () => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                    error: (e, _) => Text(
                      'Could not load history.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    data: (txs) {
                      if (txs.isEmpty) {
                        return GlassPanel(
                          blurred: false,
                          padding: const EdgeInsets.all(22),
                          child: Center(
                            child: Text(
                              'No transactions in this account yet.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        );
                      }
                      return GlassPanel(
                        blurred: false,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          children: [for (final t in txs) TransactionRow(item: t, showDate: true)],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 96),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  static String _kindLabel(AccountKind kind) => switch (kind) {
        AccountKind.cash => 'Cash',
        AccountKind.bank => 'Bank account',
        AccountKind.savings => 'Savings',
        AccountKind.wallet => 'Digital wallet',
      };
}
