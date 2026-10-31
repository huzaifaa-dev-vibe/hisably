import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/haptics/app_haptics.dart';
import '../../core/money/currency.dart';
import '../../core/money/money.dart';
import '../../core/money/money_formatter.dart';
import '../../core/theme/aurora_background.dart';
import '../../core/theme/glass.dart';
import '../../core/theme/icon_registry.dart';
import '../../core/theme/theme_spec.dart';
import '../../data/providers.dart';
import '../../data/quick_add/quick_add_controller.dart' show QuickKey;
import '../quick_add/keypad.dart';

/// Account-to-account transfer. Same-currency only — cross-currency moves
/// must use Currency Exchange so both amounts stay preserved.
class TransferScreen extends ConsumerStatefulWidget {
  const TransferScreen({super.key});

  @override
  ConsumerState<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends ConsumerState<TransferScreen> {
  int? _fromId;
  int? _toId;
  String _raw = '0';
  final _noteController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final currency = _selectedCurrency(accounts);
    final amount = Money.tryParseRaw(_raw, currency);
    final canSave =
        _fromId != null && _toId != null && _fromId != _toId && amount != null && amount.isPositive && !_saving;

    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('Transfer'),
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
                    _AccountPickers(
                      accounts: accounts,
                      fromId: _fromId,
                      toId: _toId,
                      onFrom: (id) => setState(() => _fromId = id),
                      onTo: (id) => setState(() => _toId = id),
                    ),
                    const SizedBox(height: 18),
                    Center(
                      child: Text(
                        '${currency.symbol.isEmpty ? currency.code : currency.symbol} '
                        '${AmountFormat.typing(_raw, currency)}',
                        style: Theme.of(context)
                            .textTheme
                            .displayMedium!
                            .copyWith(fontFeatures: [FontFeature.tabularFigures()]),
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _noteController,
                      maxLength: 80,
                      decoration: const InputDecoration(
                        hintText: 'Optional note',
                        counterText: '',
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(_error!,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall!
                              .copyWith(color: context.expenseColor)),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
                child: KeypadGrid(
                  onKey: _pressKey,
                  onClear: () => setState(() => _raw = '0'),
                  decimalEnabled: currency.decimalDigits > 0,
                  semanticPrefix: 'Transfer amount',
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
                child: SizedBox(
                  height: 54,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: context.spec.transfer,
                      foregroundColor: Colors.black,
                      disabledBackgroundColor:
                          context.spec.transfer.withValues(alpha: 0.35),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22)),
                    ),
                    onPressed: canSave ? _save : null,
                    child: Text(_saving ? 'Transferring…' : 'Transfer'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Currency _selectedCurrency(List<Account> accounts) {
    for (final a in accounts) {
      if (a.id == _fromId || a.id == _toId) {
        return CurrencyRegistry.byCode(a.currencyCode);
      }
    }
    return CurrencyRegistry.byCode(ref.read(primaryCurrencyProvider));
  }

  void _pressKey(QuickKey k) {
    final currency = _selectedCurrency(
        ref.read(accountsProvider).value ?? const []);
    var raw = _raw;
    switch (k) {
      case QuickKey.backspace:
        if (raw.isNotEmpty) raw = raw.substring(0, raw.length - 1);
      case QuickKey.decimal:
        if (currency.decimalDigits == 0 || raw.contains('.')) return;
        raw = raw.isEmpty ? '0.' : '$raw.';
      case _:
        final d = k.index.toString();
        final dot = raw.indexOf('.');
        if (dot != -1) {
          if (raw.length - dot - 1 >= currency.decimalDigits) return;
          raw += d;
        } else if (raw == '0') {
          raw = d;
        } else if (raw.length < kMaxIntegerDigits) {
          raw += d;
        }
    }
    setState(() => _raw = raw.isEmpty ? '0' : raw);
  }

  Future<void> _save() async {
    final accounts = ref.read(accountsProvider).value ?? const [];
    final currency = _selectedCurrency(accounts);
    final amount = Money.tryParseRaw(_raw, currency);
    if (amount == null || _fromId == null || _toId == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = await ref.read(transactionRepositoryProvider).addTransfer(
            fromAccountId: _fromId!,
            toAccountId: _toId!,
            amountMinor: amount.minorUnits,
            note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
          );
      AppHaptics.success();
      if (mounted) Navigator.of(context).pop(id);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = e is Exception && e.toString().contains('currencyMismatch')
            ? 'Transfers require two accounts in the same currency. Use Currency Exchange instead.'
            : 'Could not complete the transfer. Please check the accounts and amount.';
      });
      AppHaptics.warn();
    }
  }
}

class _AccountPickers extends StatelessWidget {
  const _AccountPickers({
    required this.accounts,
    required this.fromId,
    required this.toId,
    required this.onFrom,
    required this.onTo,
  });

  final List<Account> accounts;
  final int? fromId;
  final int? toId;
  final ValueChanged<int?> onFrom;
  final ValueChanged<int?> onTo;

  @override
  Widget build(BuildContext context) {
    final from = accounts.where((a) => a.id == fromId).firstOrNull;
    final to = accounts.where((a) => a.id == toId).firstOrNull;

    return GlassPanel(
      blurred: false,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _PickerRow(
            label: 'From',
            account: from,
            excludedId: toId,
            accounts: accounts,
            onPicked: onFrom,
          ),
          const SizedBox(height: 12),
          _PickerRow(
            label: 'To',
            account: to,
            excludedId: fromId,
            accounts: accounts,
            onPicked: onTo,
          ),
        ],
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
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
          width: 46,
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
                            leading: Icon(IconRegistry.forAccountKind(a.kind)),
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
