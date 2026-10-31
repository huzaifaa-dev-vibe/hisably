import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/db/app_database.dart';
import '../../core/haptics/app_haptics.dart';
import '../../core/money/currency.dart';
import '../../core/money/money.dart';
import '../../core/money/money_formatter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/glass.dart';
import '../../core/theme/theme_spec.dart';
import '../../data/providers.dart';

/// One person's ledger: entries newest first, running per-currency balance,
/// add entry (gave/took), settle-up and delete-entry.
class KhataDetailScreen extends ConsumerWidget {
  const KhataDetailScreen({super.key, required this.personId});

  final int personId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final personAsync = ref.watch(khataPersonProvider(personId));
    final entriesAsync = ref.watch(khataEntriesProvider(personId));
    final s = context.spec;

    final person = personAsync.value;
    if (person == null) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(backgroundColor: Colors.transparent),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final entries = entriesAsync.value ?? const <KhataEntry>[];
    final balances = <String, int>{};
    for (final e in entries) {
      final signed = e.direction == KhataDirection.gave
          ? e.amountMinor
          : -e.amountMinor;
      balances[e.currencyCode] = (balances[e.currencyCode] ?? 0) + signed;
    }

    final avatar = AppColors.personColor(person.colorKey);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: avatar.withValues(alpha: 0.2),
                border: Border.all(color: avatar.withValues(alpha: 0.45)),
              ),
              child: Center(
                child: Text(
                  person.name[0].toUpperCase(),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: avatar,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                person.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Balance summary
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: GlassPanel(
                blurred: false,
                padding: const EdgeInsets.all(18),
                child: balances.isEmpty || balances.values.every((v) => v == 0)
                    ? Column(
                        children: [
                          Text('All settled',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text(
                            'No outstanding balance in any currency.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      )
                    : Wrap(
                        spacing: 24,
                        runSpacing: 10,
                        children: [
                          for (final e in balances.entries)
                            _BalanceBadge(code: e.key, minor: e.value),
                        ],
                      ),
              ),
            ),
            // Actions
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
              child: Row(
                children: [
                  Expanded(
                    child: _EntryActionButton(
                      label: 'Gave money',
                      icon: Icons.north_east,
                      color: s.income,
                      onPressed: () => _openEntrySheet(context, ref,
                          direction: KhataDirection.gave),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _EntryActionButton(
                      label: 'Took money',
                      icon: Icons.south_west,
                      color: s.expense,
                      onPressed: () => _openEntrySheet(context, ref,
                          direction: KhataDirection.took),
                    ),
                  ),
                ],
              ),
            ),
            // Entries
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Text(
                        'No entries yet.\nRecord money you gave or took.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
                      itemCount: entries.length,
                      itemBuilder: (context, i) {
                        final e = entries[i];
                        return _EntryRow(
                          entry: e,
                          onDelete: () async {
                            final repo = ref.read(khataRepositoryProvider);
                            await repo.deleteEntry(e.id);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEntrySheet(
    BuildContext context,
    WidgetRef ref, {
    required KhataDirection direction,
  }) {
    AppHaptics.tap();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EntrySheet(personId: personId, direction: direction),
    );
  }
}

class _BalanceBadge extends StatelessWidget {
  const _BalanceBadge({required this.code, required this.minor});

  final String code;
  final int minor;

  @override
  Widget build(BuildContext context) {
    final s = context.spec;
    final c = CurrencyRegistry.byCode(code);
    final color = minor > 0
        ? s.income
        : minor < 0
            ? s.expense
            : s.textSecondary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          code,
          style: Theme.of(context).textTheme.labelSmall,
        ),
        Text(
          '${minor > 0 ? '+' : minor < 0 ? '-' : ''}'
          '${AmountFormat.money(Money.fromMinor(minor.abs(), c), includeCode: true)}',
          style: Theme.of(context).textTheme.titleLarge!.copyWith(color: color),
        ),
        Text(
          minor > 0 ? 'owes you' : minor < 0 ? 'you owe' : '',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}

class _EntryActionButton extends StatelessWidget {
  const _EntryActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final s = context.spec;
    return Material(
      color: color.withValues(alpha: s.isDark ? 0.20 : 0.12),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onPressed,
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 19, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium!
                    .copyWith(color: color, fontSize: 14.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry, required this.onDelete});

  final KhataEntry entry;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final s = context.spec;
    final gave = entry.direction == KhataDirection.gave;
    final color = gave ? s.income : s.expense;
    final c = CurrencyRegistry.byCode(entry.currencyCode);

    return Dismissible(
      key: ValueKey('khata-entry-${entry.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: s.expense.withValues(alpha: 0.14),
        ),
        child: Icon(Icons.delete_outline, color: s.expense),
      ),
      confirmDismiss: (_) async {
        AppHaptics.warn();
        return await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Delete entry?'),
                content: const Text(
                    'The balance is recalculated from the remaining entries.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: Text('Delete',
                        style: TextStyle(color: context.spec.expense)),
                  ),
                ],
              ),
            ) ??
            false;
      },
      onDismissed: (_) => onDelete(),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GlassPanel(
          blurred: false,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.14),
                  border: Border.all(color: color.withValues(alpha: 0.35)),
                ),
                child: Icon(
                  gave ? Icons.north_east : Icons.south_west,
                  size: 18,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      gave ? 'You gave' : 'You took',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (entry.note != null && entry.note!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        entry.note!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    Text(
                      DateFormat('d MMM yyyy').format(entry.occurredAt),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              Text(
                '${gave ? '+' : '-'}'
                '${AmountFormat.money(Money.fromMinor(entry.amountMinor, c))}',
                style: Theme.of(context).textTheme.titleMedium!.copyWith(
                      color: color,
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

/// Add a khata entry (gave/took), with amount, currency and note.
class _EntrySheet extends ConsumerStatefulWidget {
  const _EntrySheet({required this.personId, required this.direction});

  final int personId;
  final KhataDirection direction;

  @override
  ConsumerState<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends ConsumerState<_EntrySheet> {
  late KhataDirection _direction = widget.direction;
  final _amount = TextEditingController();
  final _note = TextEditingController();
  late String _currency;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _currency = ref.read(primaryCurrencyProvider);
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.spec;
    final totals = ref.watch(totalsByCurrencyProvider).value ?? const {};
    final currencies = totals.keys.toList()..sort();
    if (!currencies.contains(_currency) && currencies.isNotEmpty) {
      _currency = currencies.first;
    }

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
              child: Text('Add entry',
                  style: Theme.of(context).textTheme.titleLarge),
            ),
            const SizedBox(height: 16),
            // Gave / Took toggle
            Row(
              children: [
                Expanded(
                  child: _DirToggle(
                    label: 'I gave',
                    icon: Icons.north_east,
                    color: s.income,
                    selected: _direction == KhataDirection.gave,
                    s: s,
                    onTap: () => setState(() => _direction = KhataDirection.gave),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DirToggle(
                    label: 'I took',
                    icon: Icons.south_west,
                    color: s.expense,
                    selected: _direction == KhataDirection.took,
                    s: s,
                    onTap: () => setState(() => _direction = KhataDirection.took),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Amount ($_currency)'),
            ),
            if (currencies.length > 1) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  for (final code in currencies)
                    ChoiceChip(
                      label: Text(code),
                      selected: code == _currency,
                      onSelected: (_) => setState(() => _currency = code),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration:
                  const InputDecoration(labelText: 'Note (optional)'),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Save entry'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final parsed = Money.tryParseRaw(_amount.text.trim(),
        CurrencyRegistry.byCode(_currency));
    if (parsed == null || parsed.minorUnits <= 0) return;

    setState(() => _saving = true);
    AppHaptics.confirm();
    await ref.read(khataRepositoryProvider).addEntry(
          personId: widget.personId,
          direction: _direction,
          amountMinor: parsed.minorUnits,
          currencyCode: _currency,
          note: _note.text,
        );
    if (mounted) Navigator.of(context).pop();
  }
}

class _DirToggle extends StatelessWidget {
  const _DirToggle({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.s,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final AppThemeSpec s;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? color.withValues(alpha: s.isDark ? 0.26 : 0.15)
          : (s.isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.white.withValues(alpha: 0.65)),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? color.withValues(alpha: 0.8) : s.glassBorder,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 18, color: selected ? color : s.textSecondary),
              const SizedBox(width: 7),
              Text(
                label,
                style: Theme.of(context).textTheme.titleMedium!.copyWith(
                      fontSize: 14,
                      color: selected ? color : s.textSecondary,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
