import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/app_database.dart';
import '../../core/money/currency.dart';
import '../../core/money/money.dart';
import '../../core/money/money_formatter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/glass.dart';
import '../../core/theme/icon_registry.dart';
import '../../core/theme/theme_spec.dart';
import '../../data/providers.dart';

/// Account list with balances; entry point for creating accounts,
/// transfers and currency exchange.
class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountsWithBalancesProvider);
    final accounts = accountsAsync.value ?? const <AccountWithBalance>[];

    return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('Accounts'),
          actions: [
            IconButton(
              tooltip: 'Transfer between accounts',
              icon: const Icon(Icons.swap_horiz_rounded),
              onPressed: () => context.push('/transfer'),
            ),
            IconButton(
              tooltip: 'Currency exchange',
              icon: const Icon(Icons.currency_exchange_rounded),
              onPressed: () => context.push('/exchange'),
            ),
          ],
        ),
        body: SafeArea(
          bottom: false,
          child: accounts.isEmpty
              ? _EmptyAccounts(onCreate: () => _openNewAccountSheet(context))
              : ListView(
                  padding: AppDimens.pagePadding,
                  children: [
                    const SizedBox(height: 8),
                    for (final ab in accounts)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: GlassPanel(
                          blurred: false,
                          onTap: () => context.push('/accounts/${ab.account.id}'),
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              _kindBubble(ab.account),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      ab.account.name,
                                      style: Theme.of(context).textTheme.titleMedium,
                                    ),
                                    Text(
                                      _kindLabel(ab.account.kind),
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    _balance(ab),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium!
                                        .copyWith(
                                          fontFeatures: [FontFeature.tabularFigures()],
                                          color: ab.balanceMinor < 0 ? context.expenseColor : null,
                                        ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    ab.account.currencyCode,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall!
                                        .copyWith(letterSpacing: 0.6),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                Icons.chevron_right,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Center(
                      child: TextButton.icon(
                        onPressed: () => _openNewAccountSheet(context),
                        icon: const Icon(Icons.add),
                        label: const Text('New account'),
                      ),
                    ),
                    const SizedBox(height: 96),
                  ],
                ),
      ),
    );
  }

  static Widget _kindBubble(Account account) {
    final color = AppColors.accountColor(account.colorKey);
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.18),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Icon(IconRegistry.forAccountKind(account.kind), size: 20, color: color),
    );
  }

  static String _kindLabel(AccountKind kind) => switch (kind) {
        AccountKind.cash => 'Cash',
        AccountKind.bank => 'Bank account',
        AccountKind.savings => 'Savings',
        AccountKind.wallet => 'Digital wallet',
      };

  // Derived balances may be negative; AmountFormat.money renders the sign.
  static String _balance(AccountWithBalance ab) => AmountFormat.money(
        Money.fromSigned(ab.balanceMinor, CurrencyRegistry.byCode(ab.account.currencyCode)),
        includeCode: true,
      );

  static Future<void> _openNewAccountSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF141822)
          : Colors.white,
      builder: (_) => const NewAccountSheet(),
    );
  }
}

class _EmptyAccounts extends StatelessWidget {
  const _EmptyAccounts({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GlassPanel(
              blurred: true,
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 44,
                    color: context.accent,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Create your first account',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Track cash, bank, savings and digital wallets separately — each with its own currency.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('New account'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet for creating an account: name, kind, currency, opening
/// balance and an accent color.
class NewAccountSheet extends ConsumerStatefulWidget {
  const NewAccountSheet({super.key});

  @override
  ConsumerState<NewAccountSheet> createState() => _NewAccountSheetState();
}

class _NewAccountSheetState extends ConsumerState<NewAccountSheet> {
  final _nameController = TextEditingController();
  final _openingController = TextEditingController();
  AccountKind _kind = AccountKind.cash;
  String _currency = 'PKR';
  String _colorKey = 'blue';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _openingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
          left: 20,
          right: 20,
          top: 6,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('New account', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 18),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                maxLength: 60,
                decoration: const InputDecoration(
                  labelText: 'Account name',
                  hintText: 'e.g. Cash in hand, HBL savings…',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 14),
              Text('Type', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final k in AccountKind.values)
                    ChoiceChip(
                      label: Text(AccountsScreen._kindLabel(k)),
                      selected: _kind == k,
                      onSelected: (_) => setState(() => _kind = k),
                      avatar: Icon(
                        IconRegistry.forAccountKind(k),
                        size: 16,
                        color: _kind == k ? context.accent : null,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Currency', style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: _pickCurrency,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Theme.of(context).dividerTheme.color!),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _currency,
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.expand_more, size: 18),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Opening balance', style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _openingController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            hintText: '0',
                            prefixText: '${CurrencyRegistry.byCode(_currency).symbol} ',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Color', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                children: [
                  for (final entry in AppColors.accountPalette.entries)
                    GestureDetector(
                      onTap: () => setState(() => _colorKey = entry.key),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: entry.value.withValues(alpha: 0.25),
                          border: Border.all(
                            color: entry.value,
                            width: _colorKey == entry.key ? 2.4 : 1,
                          ),
                        ),
                        child: _colorKey == entry.key
                            ? Icon(Icons.check, size: 16, color: entry.value)
                            : null,
                      ),
                    ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall!
                      .copyWith(color: context.expenseColor),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : 'Create account'),
                ),
              ),
              const SizedBox(height: 14),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickCurrency() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF141822)
          : Colors.white,
      builder: (_) => const _SheetCurrencyPicker(),
    );
    if (picked != null) setState(() => _currency = picked);
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please give the account a name.');
      return;
    }
    final openingRaw = _openingController.text.trim().replaceAll(',', '');
    final currency = CurrencyRegistry.byCode(_currency);
    final opening = openingRaw.isEmpty
        ? Money.zero(currency)
        : Money.tryParseRaw(openingRaw, currency);
    if (opening == null) {
      setState(() => _error =
          'Opening balance must have at most ${currency.decimalDigits} decimal place(s).');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(accountRepositoryProvider).createAccount(
            name: name,
            kind: _kind,
            currencyCode: _currency,
            openingBalanceMinor: opening.minorUnits,
            colorKey: _colorKey,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'Could not create the account. Please check the values.';
      });
    }
  }
}

/// Minimal currency list for sheets (reuses the registry).
class _SheetCurrencyPicker extends StatefulWidget {
  const _SheetCurrencyPicker();

  @override
  State<_SheetCurrencyPicker> createState() => _SheetCurrencyPickerState();
}

class _SheetCurrencyPickerState extends State<_SheetCurrencyPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toUpperCase();
    final list = q.isEmpty
        ? CurrencyRegistry.all
        : CurrencyRegistry.all
            .where((c) =>
                c.code.contains(q) || (c.englishName?.toUpperCase().contains(q) ?? false))
            .toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'Search currency',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, i) => ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  leading: SizedBox(
                    width: 52,
                    child: Text(list[i].code, style: Theme.of(context).textTheme.titleMedium),
                  ),
                  title: Text(list[i].englishName ?? list[i].code),
                  subtitle: Text('${list[i].decimalDigits} decimals'),
                  onTap: () => Navigator.of(context).pop(list[i].code),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
