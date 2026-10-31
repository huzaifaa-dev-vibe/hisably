import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/money/currency.dart';
import '../../core/money/money.dart';
import '../../core/money/money_formatter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/glass.dart';
import '../../core/theme/icon_registry.dart';
import '../../core/theme/theme_spec.dart';
import '../../core/utils/date_formats.dart';
import '../../data/providers.dart';
import '../../data/settings.dart';
import '../quick_add/transaction_row.dart';

/// Home dashboard: per-currency total balance, this-month flow, quick
/// actions, accounts and recent activity. All numbers stream from derived
/// ledger aggregates.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalsAsync = ref.watch(totalsByCurrencyProvider);
    // Family args compare by value: always pass a month-truncated key,
    // never DateTime.now() (which would create a new provider — and a new
    // live SQL stream — on every rebuild).
    final monthKey = DateTime(DateTime.now().year, DateTime.now().month);
    final monthTotalsAsync = ref.watch(monthlyTotalsProvider(monthKey));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            _Header(),
            const SizedBox(height: 18),
            _BalanceHero(totals: totalsAsync.value ?? const {}),
            const SizedBox(height: 12),
            _MonthSummary(totals: monthTotalsAsync.value ?? const []),
            const SizedBox(height: 18),
            const _QuickActions(),
            const SizedBox(height: 22),
            _AccountsSection(),
            const SizedBox(height: 22),
            const _RecentSection(),
          ],
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.spec;
    final name = ref.watch(displayNameProvider);
    return Row(
      children: [
        GestureDetector(
          onTap: () => context.go('/profile'),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [s.accent, Color.lerp(s.accent, s.transfer, 0.5)!],
              ),
            ),
            child: Center(
              child: Text(
                name.isEmpty ? 'H' : name[0].toUpperCase(),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: s.onAccent,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hi, ${name.split(' ').first}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(
                DateFormats.friendlyDate(DateTime.now()),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        GlassIconButton(
          icon: Icons.donut_small_rounded,
          tooltip: 'Reports & charts',
          onPressed: () => context.push('/reports'),
        ),
      ],
    );
  }
}

/// Total balance, grouped by currency. Currencies are NEVER summed together;
/// the primary currency (first entry) is shown large, others as chips.
class _BalanceHero extends StatelessWidget {
  const _BalanceHero({required this.totals});

  final Map<String, int> totals;

  @override
  Widget build(BuildContext context) {
    final s = context.spec;
    final entries = totals.entries.where((e) => e.value != 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final primary = entries.isEmpty ? null : entries.first;
    final rest = entries.skip(1).toList();

    return GlassPanel(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Total balance', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          if (primary == null)
            Text(
              'Add your first transaction',
              style: Theme.of(context).textTheme.titleLarge!.copyWith(
                    color: s.textTertiary,
                  ),
            )
          else
            Text(
              _fmt(primary.key, primary.value),
              style: Theme.of(context).textTheme.displayMedium,
            ),
          if (rest.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in rest)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: s.isDark
                          ? Colors.white.withValues(alpha: 0.07)
                          : Colors.black.withValues(alpha: 0.05),
                    ),
                    child: Text(
                      _fmt(e.key, e.value),
                      style: Theme.of(context).textTheme.labelMedium!.copyWith(
                            color: s.textSecondary,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _fmt(String code, int minor) {
    final c = CurrencyRegistry.byCode(code);
    // Totals are derived values and can be negative — never crash, show "-".
    return AmountFormat.money(Money.fromSigned(minor, c), includeCode: true);
  }
}

/// This-month in/out, one card per currency (max 2, like the hero).
class _MonthSummary extends StatelessWidget {
  const _MonthSummary({required this.totals});

  final List<MonthlyTotals> totals;

  @override
  Widget build(BuildContext context) {
    final shown = totals.take(2).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: _MonthCard(totals: shown[i])),
        ],
      ],
    );
  }
}

class _MonthCard extends StatelessWidget {
  const _MonthCard({required this.totals});

  final MonthlyTotals totals;

  @override
  Widget build(BuildContext context) {
    final s = context.spec;
    final currency = CurrencyRegistry.byCode(totals.currencyCode);
    return GlassPanel(
      blurred: false,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FlowLine(
            icon: Icons.south_west,
            color: s.income,
            label: 'In · ${currency.code}',
            amount: AmountFormat.money(
                Money.fromMinor(totals.incomeMinor, currency)),
          ),
          const SizedBox(height: 10),
          _FlowLine(
            icon: Icons.north_east,
            color: s.expense,
            label: 'Out · ${currency.code}',
            amount: AmountFormat.money(
                Money.fromMinor(totals.expenseMinor, currency)),
          ),
        ],
      ),
    );
  }
}

class _FlowLine extends StatelessWidget {
  const _FlowLine({
    required this.icon,
    required this.color,
    required this.label,
    required this.amount,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium!
                    .copyWith(color: color),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          amount,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge!.copyWith(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
        ),
      ],
    );
  }
}

/// One-tap access to the power features.
class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    final s = context.spec;
    final items = [
      (Icons.swap_horiz_rounded, 'Transfer', '/transfer'),
      (Icons.currency_exchange_rounded, 'Exchange', '/exchange'),
      (Icons.donut_small_rounded, 'Reports', '/reports'),
      (Icons.savings_rounded, 'Budgets', '/budgets'),
      (Icons.menu_book_rounded, 'Khata', '/khata'),
    ];
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _QuickActionChip(
              icon: items[i].$1,
              label: items[i].$2,
              s: s,
              onTap: () => context.push(items[i].$3),
            ),
          ),
        ],
      ],
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  const _QuickActionChip({
    required this.icon,
    required this.label,
    required this.s,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final AppThemeSpec s;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: s.isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: s.glassBorder),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 21, color: s.accent),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: s.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountsSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountsWithBalancesProvider);
    final accounts = accountsAsync.value ?? const <AccountWithBalance>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Accounts',
          actionLabel: 'See all',
          onAction: () => context.go('/accounts'),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 132,
          child: ListView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            children: [
              for (final a in accounts) _AccountCard(ab: a),
              const _AddAccountCard(),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final s = context.spec;
    return Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const Spacer(),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(44, 36),
            ),
            child: Text(actionLabel!, style: TextStyle(color: s.accent)),
          ),
      ],
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.ab});

  final AccountWithBalance ab;

  @override
  Widget build(BuildContext context) {
    final s = context.spec;
    final color = AppColors.accountColor(ab.account.colorKey);
    final currency = CurrencyRegistry.byCode(ab.account.currencyCode);
    final negative = ab.balanceMinor < 0;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: GlassPanel(
        blurred: false,
        onTap: () => context.push('/accounts/${ab.account.id}'),
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 168,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.2),
                      border: Border.all(color: color.withValues(alpha: 0.4)),
                    ),
                    child: Icon(
                      IconRegistry.forAccountKind(ab.account.kind),
                      size: 17,
                      color: color,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    currency.code,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall!
                        .copyWith(letterSpacing: 0.6),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                ab.account.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 2),
              Text(
                AmountFormat.money(
                    Money.fromSigned(ab.balanceMinor, currency),
                    includeCode: true),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium!.copyWith(
                      color: negative ? s.expense : s.textPrimary,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddAccountCard extends StatelessWidget {
  const _AddAccountCard();

  @override
  Widget build(BuildContext context) {
    final s = context.spec;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: GlassPanel(
        blurred: false,
        onTap: () => context.go('/accounts'),
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 120,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_circle_outline,
                size: 26,
                color: s.textSecondary,
              ),
              const SizedBox(height: 8),
              Text(
                'Add account',
                style: Theme.of(context)
                    .textTheme
                    .labelMedium!
                    .copyWith(color: s.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentSection extends ConsumerWidget {
  const _RecentSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.spec;
    final txAsync = ref.watch(recentTransactionsProvider);
    final txs = txAsync.value ?? const <TxWithRefs>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Recent activity',
          actionLabel: 'See all',
          onAction: () => context.go('/transactions'),
        ),
        const SizedBox(height: 10),
        if (txs.isEmpty)
          GlassPanel(
            blurred: false,
            padding: const EdgeInsets.all(22),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 34,
                    color: s.textTertiary,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Nothing recorded yet.\nTap the + button to log your first transaction.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          )
        else
          GlassPanel(
            blurred: false,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final tx in txs.take(5)) TransactionRow(item: tx),
              ],
            ),
          ),
      ],
    );
  }
}
