import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money/currency.dart';
import '../../core/theme/theme_spec.dart';
import '../../data/providers.dart';

/// Horizontal selector for the currency used by Quick Add. Opens a
/// bottom-sheet picker backed by the currency registry.
class CurrencySelectorChip extends ConsumerWidget {
  const CurrencySelectorChip({super.key, required this.currencyCode, required this.onChanged});

  final String currencyCode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = CurrencyRegistry.byCode(currencyCode);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _openPicker(context, ref),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Theme.of(context).dividerTheme.color!),
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.white.withValues(alpha: 0.65),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                currency.code,
                style: Theme.of(context)
                    .textTheme
                    .labelLarge!
                    .copyWith(letterSpacing: 0.4),
              ),
              const SizedBox(width: 5),
              Icon(
                Icons.expand_more,
                size: 17,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openPicker(BuildContext context, WidgetRef ref) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF141822)
          : Colors.white,
      builder: (_) => const _CurrencyPickerSheet(),
    );
    if (picked != null) onChanged(picked);
  }
}

class _CurrencyPickerSheet extends ConsumerStatefulWidget {
  const _CurrencyPickerSheet();

  @override
  ConsumerState<_CurrencyPickerSheet> createState() => _CurrencyPickerSheetState();
}

class _CurrencyPickerSheetState extends ConsumerState<_CurrencyPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final all = CurrencyRegistry.all;
    final q = _query.trim().toUpperCase();
    final filtered = q.isEmpty
        ? all
        : all
            .where((c) =>
                c.code.contains(q) ||
                (c.englishName?.toUpperCase().contains(q) ?? false))
            .toList();

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: TextField(
                autofocus: false,
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'Search currency (code or name)',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final c = filtered[i];
                  final selected = c.code == ref.read(primaryCurrencyProvider);
                  return ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    leading: SizedBox(
                      width: 52,
                      child: Text(
                        c.code,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium!
                            .copyWith(letterSpacing: 0.3),
                      ),
                    ),
                    title: Text(c.englishName ?? c.code),
                    subtitle: Text(
                      '${c.symbol.isEmpty ? '—' : c.symbol}  ·  ${c.decimalDigits} decimals',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    trailing: selected
                        ? Icon(Icons.check_rounded, color: context.accent)
                        : null,
                    onTap: () => Navigator.of(context).pop(c.code),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
