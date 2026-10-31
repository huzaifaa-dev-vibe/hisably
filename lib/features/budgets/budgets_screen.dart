import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/haptics/app_haptics.dart';
import '../../core/money/currency.dart';
import '../../core/money/money.dart';
import '../../core/money/money_formatter.dart';
import '../../core/theme/glass.dart';
import '../../core/theme/icon_registry.dart';
import '../../core/theme/theme_spec.dart';
import '../../data/providers.dart';
import '../reports/charts.dart';

/// Monthly budgets: one limit per (category, currency). Progress is derived
/// live from the ledger — editing or deleting a transaction moves the bars.
class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = DateTime(DateTime.now().year, DateTime.now().month);
    final budgetsAsync = ref.watch(budgetsWithSpentProvider(month));
    final budgets = budgetsAsync.value ?? const <BudgetWithSpent>[];
    final s = context.spec;

    // Overall: total limit vs total spent (same-currency budgets only are
    // comparable; budgets in other currencies are listed but not summed).
    final primary = ref.watch(primaryCurrencyProvider);
    final comparable =
        budgets.where((b) => b.budget.currencyCode == primary).toList();
    final totalLimit =
        comparable.fold<int>(0, (a, b) => a + b.limitMinor);
    final totalSpent =
        comparable.fold<int>(0, (a, b) => a + b.spentMinor);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Budgets'),
        actions: [
          IconButton(
            tooltip: 'Add budget',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _openBudgetSheet(context, ref),
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            if (comparable.isNotEmpty) ...[
              _TotalBudgetCard(
                limitMinor: totalLimit,
                spentMinor: totalSpent,
                currencyCode: primary,
              ),
              const SizedBox(height: 16),
            ],
            if (budgetsAsync.isLoading && budgets.isEmpty)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (budgets.isEmpty)
              GlassPanel(
                blurred: false,
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.savings_rounded, size: 36, color: s.textTertiary),
                    const SizedBox(height: 12),
                    Text(
                      'No budgets yet',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Set a monthly limit per category and watch the progress as you spend.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => _openBudgetSheet(context, ref),
                      icon: const Icon(Icons.add_rounded, size: 20),
                      label: const Text('Add your first budget'),
                    ),
                  ],
                ),
              )
            else
              Column(
                children: [
                  for (final b in budgets)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _BudgetCard(budget: b),
                    ),
                ],
              ),
            const SizedBox(height: 8),
            Text(
              'Spent amounts are derived from your expense transactions in real time.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openBudgetSheet(BuildContext context, WidgetRef ref) {
    AppHaptics.tap();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _BudgetEditSheet(),
    );
  }
}

class _TotalBudgetCard extends StatelessWidget {
  const _TotalBudgetCard({
    required this.limitMinor,
    required this.spentMinor,
    required this.currencyCode,
  });

  final int limitMinor;
  final int spentMinor;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final s = context.spec;
    final c = CurrencyRegistry.byCode(currencyCode);
    final over = spentMinor > limitMinor;
    final progress = limitMinor <= 0 ? 0.0 : spentMinor / limitMinor;
    final color = over ? s.expense : (progress >= 0.8 ? s.warn : s.income);

    return GlassPanel(
      blurred: false,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('This month', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              if (over)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: s.expense.withValues(alpha: 0.15),
                  ),
                  child: Text(
                    'Over budget',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: s.expense,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${AmountFormat.money(Money.fromMinor(spentMinor, c))}'
            ' of ${AmountFormat.money(Money.fromMinor(limitMinor, c))}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          ProgressBar(
            progress: progress,
            color: color,
          ),
        ],
      ),
    );
  }
}

class _BudgetCard extends ConsumerWidget {
  const _BudgetCard({required this.budget});

  final BudgetWithSpent budget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.spec;
    final c = CurrencyRegistry.byCode(budget.budget.currencyCode);
    final color = switch (budget.state) {
      BudgetState.ok => s.income,
      BudgetState.warning => s.warn,
      BudgetState.over => s.expense,
    };

    return GlassPanel(
      blurred: false,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.15),
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                ),
                child: Icon(
                  IconRegistry.forKey(budget.category.iconKey),
                  size: 18,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  budget.category.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Delete budget',
                icon: Icon(Icons.delete_outline, size: 20, color: s.textTertiary),
                onPressed: () async {
                  final repo = ref.read(budgetRepositoryProvider);
                  await repo.delete(budget.budget.id);
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                AmountFormat.money(Money.fromMinor(budget.spentMinor, c),
                    includeCode: true),
                style: Theme.of(context).textTheme.titleLarge!.copyWith(
                      color: color,
                    ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  'of ${AmountFormat.money(Money.fromMinor(budget.limitMinor, c))}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const Spacer(),
              Text(
                '${(budget.progress * 100).toStringAsFixed(0)}%',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge!
                    .copyWith(color: color),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ProgressBar(progress: budget.progress, color: color),
        ],
      ),
    );
  }
}

/// Add / edit a budget limit. Uses the system keyboard — this is a form,
/// not the signature amount flow.
class _BudgetEditSheet extends ConsumerStatefulWidget {
  const _BudgetEditSheet();

  @override
  ConsumerState<_BudgetEditSheet> createState() => _BudgetEditSheetState();
}

class _BudgetEditSheetState extends ConsumerState<_BudgetEditSheet> {
  int? _categoryId;
  late final TextEditingController _amount = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.spec;
    final categoriesAsync = ref.watch(categoriesProvider);
    final expenseCategories = (categoriesAsync.value ?? const <Category>[])
        .where((c) => c.direction == CategoryDirection.outflow)
        .toList();

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text('New budget',
                  style: Theme.of(context).textTheme.titleLarge),
            ),
            const SizedBox(height: 18),
            DropdownButtonFormField<int>(
              initialValue: _categoryId,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                for (final c in expenseCategories)
                  DropdownMenuItem(
                    value: c.id,
                    child: Row(
                      children: [
                        Icon(IconRegistry.forKey(c.iconKey),
                            size: 18, color: s.textSecondary),
                        const SizedBox(width: 8),
                        Text(c.name),
                      ],
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _categoryId = v),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Monthly limit (${ref.watch(primaryCurrencyProvider)})',
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Save budget'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final category = _categoryId;
    final raw = _amount.text.trim();
    if (category == null || raw.isEmpty) return;

    final currency = ref.read(primaryCurrencyProvider);
    final c = CurrencyRegistry.byCode(currency);
    final parsed = Money.tryParseRaw(raw, c);
    if (parsed == null || parsed.minorUnits <= 0) return;

    setState(() => _saving = true);
    AppHaptics.confirm();
    await ref.read(budgetRepositoryProvider).setLimit(
          categoryId: category,
          currencyCode: currency,
          monthlyLimitMinor: parsed.minorUnits,
        );
    if (mounted) Navigator.of(context).pop();
  }
}
