import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money/currency.dart';
import '../../core/money/money.dart';
import '../../core/money/money_formatter.dart';
import '../../core/theme/glass.dart';
import '../../core/theme/icon_registry.dart';
import '../../core/theme/theme_spec.dart';
import '../../data/providers.dart';
import 'charts.dart';

/// Reports & insights: four chart types over the real ledger, always scoped
/// to ONE currency at a time (currencies are never mixed):
///
/// 1. Monthly comparison bars (last 6 months in vs out)
/// 2. Balance trend line (last 30 days)
/// 3. Daily in/out bars (selected month)
/// 4. Category donut (selected month, expenses or income)
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  late String _currency;
  late DateTime _month;
  bool _donutExpense = true;

  @override
  void initState() {
    super.initState();
    _month = DateTime(DateTime.now().year, DateTime.now().month);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Default to the primary currency once the providers are available.
    _currency = ref.read(primaryCurrencyProvider);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.spec;
    final totals = ref.watch(totalsByCurrencyProvider).value ?? const {};
    final currencies = totals.keys.toList()..sort();
    if (!currencies.contains(_currency) && currencies.isNotEmpty) {
      _currency = currencies.first;
    }

    final now = DateTime.now();
    final canGoForward =
        _month.isBefore(DateTime(now.year, now.month));

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Reports'),
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            _CurrencyPicker(
              currencies: currencies,
              selected: _currency,
              onChanged: (c) => setState(() => _currency = c),
            ),
            const SizedBox(height: 18),
            _SectionCard(
              title: 'In vs Out · last 6 months',
              child: _MonthlyFlowChart(currency: _currency),
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Balance · last 30 days',
              child: _BalanceTrendChart(currency: _currency),
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Daily flow',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: canGoBack(_month)
                        ? () => setState(() => _month =
                            DateTime(_month.year, _month.month - 1))
                        : null,
                    icon: const Icon(Icons.chevron_left, size: 20),
                    tooltip: 'Previous month',
                  ),
                  Text(
                    DateFormat('MMM yyyy').format(_month),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: canGoForward
                        ? () => setState(() =>
                            _month = DateTime(_month.year, _month.month + 1))
                        : null,
                    icon: const Icon(Icons.chevron_right, size: 20),
                    tooltip: 'Next month',
                  ),
                ],
              ),
              child: _DailyFlowChart(currency: _currency, month: _month),
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'By category',
              trailing: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Out')),
                  ButtonSegment(value: false, label: Text('In')),
                ],
                selected: {_donutExpense},
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  side: WidgetStatePropertyAll(BorderSide(color: s.glassBorder)),
                  backgroundColor: WidgetStateProperty.resolveWith((states) =>
                      states.contains(WidgetState.selected)
                          ? s.accent.withValues(alpha: 0.18)
                          : Colors.transparent),
                  foregroundColor: WidgetStateProperty.resolveWith((states) =>
                      states.contains(WidgetState.selected)
                          ? s.accent
                          : s.textSecondary),
                ),
                onSelectionChanged: (v) =>
                    setState(() => _donutExpense = v.first),
              ),
              child: _CategoryDonut(
                currency: _currency,
                month: _month,
                expense: _donutExpense,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static bool canGoBack(DateTime month) {
    final now = DateTime.now();
    // Allow browsing back up to 24 months — enough for personal history.
    return now.difference(month).inDays < 365 * 2;
  }
}

// ---------------------------------------------------------------------------
// Currency picker chips
// ---------------------------------------------------------------------------

class _CurrencyPicker extends StatelessWidget {
  const _CurrencyPicker({
    required this.currencies,
    required this.selected,
    required this.onChanged,
  });

  final List<String> currencies;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = context.spec;
    if (currencies.length <= 1) {
      return Row(
        children: [
          _Chip(
            label: currencies.isEmpty ? '—' : currencies.first,
            selected: true,
            s: s,
            onTap: null,
          ),
          const SizedBox(width: 8),
          Text(
            'Charts never mix currencies',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in currencies)
          _Chip(
            label: c,
            selected: c == selected,
            s: s,
            onTap: () => onChanged(c),
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.s,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final AppThemeSpec s;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Currency $label',
      child: Material(
        color: selected
            ? s.accent.withValues(alpha: s.isDark ? 0.24 : 0.15)
            : (s.isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.white.withValues(alpha: 0.7)),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? s.accent.withValues(alpha: 0.8) : s.glassBorder,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? s.accent : s.textPrimary,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section card
// ---------------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      blurred: false,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chart bodies
// ---------------------------------------------------------------------------

class _MonthlyFlowChart extends ConsumerWidget {
  const _MonthlyFlowChart({required this.currency});

  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.spec;
    final series = ref.watch(monthlyFlowProvider(currency)).value;
    if (series == null) {
      return const Center(
          child: Padding(
        padding: EdgeInsets.all(28),
        child: CircularProgressIndicator(),
      ));
    }

    final maxV = series
        .expand((m) => [m.inMinor, m.outMinor])
        .fold<int>(0, (a, b) => a > b ? a : b);
    final groups = [
      for (final m in series)
        (
          DateFormat('MMM').format(m.month),
          m.inMinor.toDouble(),
          m.outMinor.toDouble(),
        ),
    ];

    if (maxV == 0) return const _EmptyChart();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GroupedBarChart(groups: groups, maxValue: maxV.toDouble(), height: 160),
        const SizedBox(height: 10),
        _Legend(items: [
          ('In', s.income),
          ('Out', s.expense),
        ]),
      ],
    );
  }
}

class _BalanceTrendChart extends ConsumerWidget {
  const _BalanceTrendChart({required this.currency});

  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final series = ref.watch(balanceSeriesProvider(currency)).value;
    if (series == null) {
      return const Center(
          child: Padding(
        padding: EdgeInsets.all(28),
        child: CircularProgressIndicator(),
      ));
    }
    if (series.isEmpty) return const _EmptyChart();

    final values = series.map((p) => p.balanceMinor.toDouble()).toList();
    var minV = values.reduce((a, b) => a < b ? a : b);
    var maxV = values.reduce((a, b) => a > b ? a : b);
    if (minV == maxV) {
      minV -= 1;
      maxV += 1;
    }

    final current = series.last;
    final c = CurrencyRegistry.byCode(currency);
    final prev = series.first;
    final delta = current.balanceMinor - prev.balanceMinor;
    final s = context.spec;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              AmountFormat.money(
                  Money.fromSigned(current.balanceMinor, c), includeCode: true),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(width: 8),
            if (delta != 0)
              Text(
                '${delta > 0 ? '+' : '-'}${AmountFormat.money(Money.fromMinor(delta.abs(), c))}',
                style: Theme.of(context).textTheme.labelMedium!.copyWith(
                      color: delta > 0 ? s.income : s.expense,
                    ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TrendLineChart(values: values, minValue: minV, maxValue: maxV, height: 150),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              DateFormat('d MMM').format(series.first.date),
              style: Theme.of(context).textTheme.labelSmall,
            ),
            Text(
              'Today',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ],
    );
  }
}

class _DailyFlowChart extends ConsumerWidget {
  const _DailyFlowChart({required this.currency, required this.month});

  final String currency;
  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.spec;
    final series =
        ref.watch(dailyFlowProvider((month: month, currency: currency))).value;
    if (series == null) {
      return const Center(
          child: Padding(
        padding: EdgeInsets.all(28),
        child: CircularProgressIndicator(),
      ));
    }

    final maxV = series
        .expand((d) => [d.inMinor, d.outMinor])
        .fold<int>(0, (a, b) => a > b ? a : b);
    if (maxV == 0) return const _EmptyChart();

    final labelEvery = series.length > 20 ? 5 : 2;
    final groups = [
      for (final d in series)
        (
          d.day % labelEvery == 0 || d.day == 1 ? '${d.day}' : '',
          d.inMinor.toDouble(),
          d.outMinor.toDouble(),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GroupedBarChart(
          groups: groups,
          maxValue: maxV.toDouble(),
          height: 160,
          labelEvery: labelEvery,
        ),
        const SizedBox(height: 10),
        _Legend(items: [
          ('In', s.income),
          ('Out', s.expense),
        ]),
      ],
    );
  }
}

class _CategoryDonut extends ConsumerWidget {
  const _CategoryDonut({
    required this.currency,
    required this.month,
    required this.expense,
  });

  final String currency;
  final DateTime month;
  final bool expense;

  static const _sliceColors = <Color>[
    Color(0xFF5B8DEF), // blue
    Color(0xFF2BC5B4), // teal
    Color(0xFF9B7BFF), // violet
    Color(0xFFFFB74D), // amber
    Color(0xFFFF7A93), // rose
    Color(0xFF3DDC84), // green
    Color(0xFF6E9EFF), // sky
    Color(0xFFE5A15A), // ochre
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.spec;
    final slices = ref
        .watch(categoryBreakdownProvider(
          (month: month, currency: currency, expense: expense),
        ))
        .value;

    if (slices == null) {
      return const Center(
          child: Padding(
        padding: EdgeInsets.all(28),
        child: CircularProgressIndicator(),
      ));
    }

    if (slices.isEmpty) return const _EmptyChart();

    final total = slices.fold<int>(0, (a, b) => a + b.totalMinor);
    final c = CurrencyRegistry.byCode(currency);

    final donutSlices = [
      for (var i = 0; i < slices.length; i++)
        DonutSlice(
          value: slices[i].totalMinor.toDouble(),
          color: _sliceColors[i % _sliceColors.length],
        ),
    ];

    return Column(
      children: [
        Row(
          children: [
            DonutChart(
              slices: donutSlices,
              centerSublabel: expense ? 'Spent' : 'Earned',
              centerLabel: AmountFormat.compact(Money.fromMinor(total, c)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < slices.length && i < 6; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _sliceColors[i % _sliceColors.length],
                            ),
                          ),
                          const SizedBox(width: 7),
                          Icon(
                            IconRegistry.forKey(slices[i].iconKey),
                            size: 13,
                            color: s.textTertiary,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              slices[i].name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium!
                                  .copyWith(color: s.textPrimary),
                            ),
                          ),
                          Text(
                            '${(slices[i].totalMinor * 100 / total).toStringAsFixed(0)}%',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  if (slices.length > 6)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '+ ${slices.length - 6} more',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _EmptyChart extends StatelessWidget {
  const _EmptyChart();

  @override
  Widget build(BuildContext context) {
    final s = context.spec;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 34),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.bar_chart_rounded, size: 30, color: s.textTertiary),
            const SizedBox(height: 8),
            Text(
              'No data for this period yet',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.items});

  final List<(String, Color)> items;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (label, color) in items) ...[
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 5),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(width: 16),
        ],
      ],
    );
  }
}
