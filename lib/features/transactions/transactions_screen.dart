import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/glass.dart';
import '../../core/utils/date_formats.dart';
import '../../data/providers.dart';
import '../quick_add/transaction_row.dart';

/// Filter state for the history screen.
class HistoryFilterState {
  const HistoryFilterState({
    this.type = TxTypeFilter.all,
    this.search = '',
  });

  final TxTypeFilter type;
  final String search;

  HistoryFilterState copyWith({TxTypeFilter? type, String? search}) =>
      HistoryFilterState(type: type ?? this.type, search: search ?? this.search);

  @override
  bool operator ==(Object other) =>
      other is HistoryFilterState && other.type == type && other.search == search;

  @override
  int get hashCode => Object.hash(type, search);
}

class HistoryFilterNotifier extends Notifier<HistoryFilterState> {
  @override
  HistoryFilterState build() => const HistoryFilterState();

  void setType(TxTypeFilter t) => state = state.copyWith(type: t);
  void setSearch(String s) => state = state.copyWith(search: s);
}

final historyFilterProvider =
    NotifierProvider<HistoryFilterNotifier, HistoryFilterState>(
  HistoryFilterNotifier.new,
);

/// Transaction history with type filters and text search.
class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(historyFilterProvider);
    final txsAsync = ref.watch(
      accountTransactionsProvider(
        TxQueryFilter(
          type: filter.type,
          search: filter.search.isEmpty ? null : filter.search,
          limit: 400,
        ),
      ),
    );

    return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('History'),
        ),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                child: TextField(
                  onChanged: ref.read(historyFilterProvider.notifier).setSearch,
                  decoration: const InputDecoration(
                    hintText: 'Search notes and categories',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    for (final t in TxTypeFilter.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _FilterChip(
                          label: _labelFor(t),
                          selected: filter.type == t,
                          onTap: () =>
                              ref.read(historyFilterProvider.notifier).setType(t),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: txsAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: Text('Could not load history.',
                        style: Theme.of(context).textTheme.bodyMedium),
                  ),
                  data: (txs) {
                    if (txs.isEmpty) {
                      return Center(
                        child: Text(
                          'No transactions match.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      );
                    }
                    // Group by day.
                    final groups = <DateTime, List<TxWithRefs>>{};
                    for (final t in txs) {
                      final day = DateFormats.dayStart(t.tx.occurredAt);
                      (groups[day] ??= []).add(t);
                    }
                    final days = groups.keys.toList()
                      ..sort((a, b) => b.compareTo(a));
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                      child: GlassPanel(
                      blurred: false,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: ListView.builder(
                        itemCount: days.length,
                        itemBuilder: (context, i) {
                          final day = days[i];
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 12, 16, 4),
                                child: Text(
                                  DateFormats.friendlyDate(day),
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium!
                                      .copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                              ),
                              for (final t in groups[day]!)
                                TransactionRow(item: t, showDate: false),
                              if (i != days.length - 1)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                  child: Divider(
                                      color: Theme.of(context)
                                          .dividerTheme
                                          .color),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  );
                },
                ),
              ),
            ],
          ),
      ),
    );
  }

  static String _labelFor(TxTypeFilter t) => switch (t) {
        TxTypeFilter.all => 'All',
        TxTypeFilter.income => 'In',
        TxTypeFilter.expense => 'Out',
        TxTypeFilter.transfers => 'Transfers',
      };
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bright = Theme.of(context).brightness;
    return Material(
      color: selected
          ? AppColorsAccentChip.color(context)
          : bright == Brightness.dark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.white.withValues(alpha: 0.62),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? AppColorsAccentChip.color(context)
                  : bright == Brightness.dark
                      ? AppColorsBorder.dark
                      : AppColorsBorder.light,
            ),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge!.copyWith(
                  fontSize: 13.5,
                  color: selected ? Colors.black : null,
                ),
          ),
        ),
      ),
    );
  }
}

/// Local namespace to avoid importing colors file in two names.
abstract final class AppColorsAccentChip {
  static Color color(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF6C9EFF)
          : const Color(0xFF5B8DEF);
}

abstract final class AppColorsBorder {
  static const dark = Color(0x1AFFFFFF);
  static const light = Color(0x59FFFFFF);
}
