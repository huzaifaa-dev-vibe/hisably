import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/app_database.dart';
import '../../core/haptics/app_haptics.dart';
import '../../core/money/currency.dart';
import '../../core/money/money.dart';
import '../../core/money/money_formatter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/glass.dart';
import '../../core/theme/theme_spec.dart';
import '../../data/providers.dart';

/// The personal khata: who owes whom, across currencies. Balances are
/// always derived from entries — positive means they owe you.
class KhataScreen extends ConsumerWidget {
  const KhataScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peopleAsync = ref.watch(khataPeopleProvider);
    final people = peopleAsync.value ?? const <PersonWithBalance>[];
    final s = context.spec;

    // Net position across people, per currency (never mixed).
    final netByCurrency = <String, int>{};
    for (final p in people) {
      for (final e in p.balanceByCurrency.entries) {
        netByCurrency[e.key] = (netByCurrency[e.key] ?? 0) + e.value;
      }
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Khata'),
        actions: [
          IconButton(
            tooltip: 'Add person',
            icon: const Icon(Icons.person_add_alt_rounded),
            onPressed: () => _openPersonSheet(context, ref),
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            if (netByCurrency.isNotEmpty) ...[
              GlassPanel(
                blurred: false,
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Net position',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 14,
                      runSpacing: 8,
                      children: [
                        for (final e in netByCurrency.entries)
                          _NetBadge(code: e.key, minor: e.value),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (peopleAsync.isLoading && people.isEmpty)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (people.isEmpty)
              GlassPanel(
                blurred: false,
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.menu_book_rounded,
                        size: 36, color: s.textTertiary),
                    const SizedBox(height: 12),
                    Text(
                      'Your digital khata',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Keep track of money you lent or borrowed — with friends, family, anyone. Partial repayments and settlement supported.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => _openPersonSheet(context, ref),
                      icon: const Icon(Icons.person_add_alt_rounded, size: 20),
                      label: const Text('Add first person'),
                    ),
                  ],
                ),
              )
            else
              Column(
                children: [
                  for (final p in people)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _PersonCard(pwb: p),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPersonSheet(BuildContext context, WidgetRef ref,
      {KhataPerson? existing}) {
    AppHaptics.tap();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PersonSheet(existing: existing),
    );
  }
}

class _NetBadge extends StatelessWidget {
  const _NetBadge({required this.code, required this.minor});

  final String code;
  final int minor;

  @override
  Widget build(BuildContext context) {
    final s = context.spec;
    final c = CurrencyRegistry.byCode(code);
    final positive = minor > 0;
    final neutral = minor == 0;
    final color = neutral
        ? s.textSecondary
        : positive
            ? s.income
            : s.expense;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          minor == 0
              ? 'Settled'
              : positive
                  ? 'You are owed'
                  : 'You owe',
          style: Theme.of(context).textTheme.labelSmall,
        ),
        Text(
          '${minor > 0 ? '+' : minor < 0 ? '-' : ''}'
          '${AmountFormat.money(Money.fromMinor(minor.abs(), c), includeCode: true)}',
          style: Theme.of(context).textTheme.titleLarge!.copyWith(color: color),
        ),
      ],
    );
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.pwb});

  final PersonWithBalance pwb;

  @override
  Widget build(BuildContext context) {
    final s = context.spec;
    final primary = pwb.primaryBalance;
    final color = primary == null
        ? s.textSecondary
        : primary.value > 0
            ? s.income
            : s.expense;
    final avatar = AppColors.personColor(pwb.person.colorKey);

    return GlassPanel(
      blurred: false,
      onTap: () => context.push('/khata/${pwb.person.id}'),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: avatar.withValues(alpha: 0.2),
              border: Border.all(color: avatar.withValues(alpha: 0.45)),
            ),
            child: Center(
              child: Text(
                pwb.person.name.isEmpty ? '?' : pwb.person.name[0].toUpperCase(),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: avatar,
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
                  pwb.person.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  pwb.isSettled
                      ? 'All settled'
                      : primary!.value > 0
                          ? 'Owes you'
                          : 'You owe them',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall!
                      .copyWith(color: s.textSecondary),
                ),
              ],
            ),
          ),
          if (primary != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${primary.value > 0 ? '+' : '-'}'
                  '${AmountFormat.money(Money.fromMinor(primary.value.abs(), CurrencyRegistry.byCode(primary.key)))}',
                  style: Theme.of(context).textTheme.titleMedium!.copyWith(
                        color: color,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                ),
                Text(
                  primary.key,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            )
          else
            Icon(Icons.chevron_right, color: s.textTertiary),
        ],
      ),
    );
  }
}

/// Add or rename a person.
class _PersonSheet extends ConsumerStatefulWidget {
  const _PersonSheet({this.existing});

  final KhataPerson? existing;

  @override
  ConsumerState<_PersonSheet> createState() => _PersonSheetState();
}

class _PersonSheetState extends ConsumerState<_PersonSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _phone =
      TextEditingController(text: widget.existing?.phone ?? '');
  late final TextEditingController _note =
      TextEditingController(text: widget.existing?.note ?? '');
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
              child: Text(
                widget.existing == null ? 'Add person' : 'Edit person',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _name,
              autofocus: widget.existing == null,
              decoration: InputDecoration(
                labelText: 'Name',
                errorText: _error,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration:
                  const InputDecoration(labelText: 'Phone (optional)'),
            ),
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
                child: Text(_saving ? 'Saving…' : 'Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final repo = ref.read(khataRepositoryProvider);
    if (widget.existing == null) {
      await repo.addPerson(
        name: name,
        phone: _phone.text,
        note: _note.text,
        colorKey: AppColors.personPalette.keys.elementAt(_name.text.hashCode.abs() % 6),
      );
    } else {
      await repo.updatePerson(
        id: widget.existing!.id,
        name: name,
        phone: _phone.text,
        note: _note.text,
      );
    }
    AppHaptics.confirm();
    if (mounted) Navigator.of(context).pop();
  }
}
