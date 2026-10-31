import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/haptics/app_haptics.dart';
import '../../core/money/currency.dart';
import '../../core/money/money.dart';
import '../../core/money/money_formatter.dart';
import '../../core/theme/aurora_background.dart';
import '../../core/theme/glass.dart';
import '../../core/theme/theme_spec.dart';
import '../../data/providers.dart';
import '../../data/quick_add/quick_add_controller.dart' show QuickKey;
import '../quick_add/keypad.dart';

enum _Editing { source, destination }

/// Manual currency exchange between two accounts.
///
/// The user types BOTH the source amount and the destination amount they
/// actually received; the effective rate is derived live with exact integer
/// long division and is never stored. Source debit = amount + fee.
class ExchangeScreen extends ConsumerStatefulWidget {
  const ExchangeScreen({super.key});

  @override
  ConsumerState<ExchangeScreen> createState() => _ExchangeScreenState();
}

class _ExchangeScreenState extends ConsumerState<ExchangeScreen> {
  int? _fromId;
  int? _toId;
  String _srcRaw = '0';
  String _dstRaw = '0';
  int _feeMinor = 0;
  _Editing _editing = _Editing.source;
  final _feeController = TextEditingController();
  final _noteController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _feeController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final from = accounts.where((a) => a.id == _fromId).firstOrNull;
    final to = accounts.where((a) => a.id == _toId).firstOrNull;
    final srcCur = CurrencyRegistry.byCode(from?.currencyCode ?? ref.read(primaryCurrencyProvider));
    final dstCur = CurrencyRegistry.byCode(to?.currencyCode ?? 'USD');

    final srcAmount = Money.tryParseRaw(_srcRaw, srcCur);
    final dstAmount = Money.tryParseRaw(_dstRaw, dstCur);

    final rateVisible = srcAmount != null && srcAmount.isPositive && dstAmount != null && dstAmount.isPositive;
    final canSave = from != null &&
        to != null &&
        from.id != to.id &&
        srcAmount != null &&
        srcAmount.isPositive &&
        dstAmount != null &&
        dstAmount.isPositive &&
        !_saving;

    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('Currency exchange'),
        ),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    const SizedBox(height: 4),
                    GlassPanel(
                      blurred: false,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _AccountPicker(
                            label: 'From (you pay)',
                            account: from,
                            excludedId: _toId,
                            accounts: accounts,
                            onPicked: (id) => setState(() => _fromId = id),
                          ),
                          const SizedBox(height: 12),
                          _AccountPicker(
                            label: 'To (you receive)',
                            account: to,
                            excludedId: _fromId,
                            accounts: accounts,
                            onPicked: (id) => setState(() => _toId = id),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _AmountCard(
                      title: 'Source amount · ${srcCur.code}',
                      raw: _srcRaw,
                      currency: srcCur,
                      selected: _editing == _Editing.source,
                      onTap: () => setState(() => _editing = _Editing.source),
                    ),
                    const SizedBox(height: 10),
                    _AmountCard(
                      title: 'Destination amount · ${dstCur.code}',
                      raw: _dstRaw,
                      currency: dstCur,
                      selected: _editing == _Editing.destination,
                      onTap: () => setState(() => _editing = _Editing.destination),
                    ),
                    const SizedBox(height: 14),
                    if (rateVisible)
                      GlassPanel(
                        blurred: false,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                        child: Row(
                          children: [
                            Icon(Icons.percent, size: 18, color: context.accent),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Effective rate: 1 ${srcCur.code} = '
                                '${AmountFormat.ratio(dstAmount.minorUnits, srcAmount.minorUnits, dp: 6)} '
                                '${dstCur.code}',
                                style: Theme.of(context).textTheme.titleMedium!.copyWith(
                                      fontFeatures: [FontFeature.tabularFigures()],
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _feeController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: _updateFee,
                            decoration: InputDecoration(
                              labelText: 'Fee (${srcCur.code}, optional)',
                              hintText: '0',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _noteController,
                            maxLength: 60,
                            decoration: const InputDecoration(
                              labelText: 'Note (optional)',
                              counterText: '',
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall!
                              .copyWith(color: context.expenseColor)),
                    ],
                    const SizedBox(height: 10),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
                child: KeypadGrid(
                  onKey: _pressKey,
                  onClear: () => setState(() => _editing == _Editing.source
                      ? _srcRaw = '0'
                      : _dstRaw = '0'),
                  decimalEnabled: true,
                  semanticPrefix: _editing == _Editing.source
                      ? 'Source amount'
                      : 'Destination amount',
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
                child: SizedBox(
                  height: 54,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: context.spec.warn,
                      foregroundColor: Colors.black,
                      disabledBackgroundColor: context.spec.warn.withValues(alpha: 0.35),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                    ),
                    onPressed: canSave ? _save : null,
                    child: Text(_saving ? 'Saving…' : 'Record exchange'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _updateFee(String v) {
    final from = ref
        .read(accountsProvider)
        .value
        ?.where((a) => a.id == _fromId)
        .firstOrNull;
    final cur = CurrencyRegistry.byCode(from?.currencyCode ?? ref.read(primaryCurrencyProvider));
    final fee = Money.tryParseRaw(v.trim().replaceAll(',', ''), cur);
    setState(() => _feeMinor = fee?.minorUnits ?? 0);
  }

  void _pressKey(QuickKey k) {
    final cur = _editing == _Editing.source ? _srcRaw : _dstRaw;
    String next = cur;
    switch (k) {
      case QuickKey.backspace:
        if (cur.isNotEmpty) next = cur.substring(0, cur.length - 1);
      case QuickKey.decimal:
        if (cur.contains('.')) return;
        next = cur.isEmpty ? '0.' : '$cur.';
      case _:
        final d = k.index.toString();
        final dot = cur.indexOf('.');
        if (dot != -1) {
          if (cur.length - dot - 1 >= 3) return; // max 3 dp in any currency
          next = cur + d;
        } else if (cur == '0') {
          next = d;
        } else if (cur.length < kMaxIntegerDigits) {
          next = cur + d;
        }
    }
    next = next.isEmpty ? '0' : next;
    setState(() {
      if (_editing == _Editing.source) {
        _srcRaw = next;
      } else {
        _dstRaw = next;
      }
    });
  }

  Future<void> _save() async {
    final accounts = ref.read(accountsProvider).value ?? const [];
    final from = accounts.where((a) => a.id == _fromId).firstOrNull;
    final to = accounts.where((a) => a.id == _toId).firstOrNull;
    if (from == null || to == null) return;
    final srcCur = CurrencyRegistry.byCode(from.currencyCode);
    final dstCur = CurrencyRegistry.byCode(to.currencyCode);
    final srcAmount = Money.tryParseRaw(_srcRaw, srcCur);
    final dstAmount = Money.tryParseRaw(_dstRaw, dstCur);
    if (srcAmount == null || dstAmount == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = await ref.read(transactionRepositoryProvider).addExchange(
            fromAccountId: from.id,
            toAccountId: to.id,
            amountMinor: srcAmount.minorUnits,
            toAmountMinor: dstAmount.minorUnits,
            feeMinor: _feeMinor,
            note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
          );
      AppHaptics.success();
      if (mounted) Navigator.of(context).pop(id);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'Could not record the exchange. Please check the amounts.';
      });
      AppHaptics.warn();
    }
  }
}

class _AmountCard extends StatelessWidget {
  const _AmountCard({
    required this.title,
    required this.raw,
    required this.currency,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String raw;
  final Currency currency;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      blurred: false,
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      borderColor:
          selected ? context.accent.withValues(alpha: 0.6) : null,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                Text(
                  AmountFormat.typing(raw, currency),
                  style: Theme.of(context)
                      .textTheme
                      .displaySmall!
                      .copyWith(fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ],
            ),
          ),
          if (selected)
            Icon(Icons.radio_button_checked, color: context.accent, size: 22)
          else
            Icon(
              Icons.radio_button_off,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 22,
            ),
        ],
      ),
    );
  }
}

class _AccountPicker extends StatelessWidget {
  const _AccountPicker({
    required this.label,
    required this.account,
    required this.accounts,
    required this.excludedId,
    required this.onPicked,
  });

  final String label;
  final Account? account;
  final List<Account> accounts;
  final int? excludedId;
  final ValueChanged<int?> onPicked;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 118,
          child: Text(label, style: Theme.of(context).textTheme.titleSmall),
        ),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () async {
              final picked = await showModalBottomSheet<int>(
                context: context,
                showDragHandle: true,
                backgroundColor: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF141822)
                    : Colors.white,
                builder: (ctx) => SafeArea(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final a in accounts)
                        if (a.id != excludedId)
                          ListTile(
                            title: Text(a.name),
                            subtitle: Text(a.currencyCode),
                            onTap: () => Navigator.of(ctx).pop(a.id),
                          ),
                    ],
                  ),
                ),
              );
              onPicked(picked);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Theme.of(context).dividerTheme.color!),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      account?.name ?? 'Select account',
                      style: Theme.of(context).textTheme.titleMedium!.copyWith(
                            color: account == null
                                ? Theme.of(context).colorScheme.onSurfaceVariant
                                : null,
                          ),
                    ),
                  ),
                  const Icon(Icons.expand_more, size: 20),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
