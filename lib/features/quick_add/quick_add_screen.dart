import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/db/app_database.dart';
import '../../core/haptics/app_haptics.dart';
import '../../core/money/currency.dart';
import '../../core/money/money.dart';
import '../../core/money/money_formatter.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/glass.dart';
import '../../core/theme/icon_registry.dart';
import '../../core/theme/theme_spec.dart';
import '../../data/providers.dart';
import '../../data/quick_add/quick_add_controller.dart';
import 'amount_display.dart';
import 'currency_selector_chip.dart';
import 'keypad.dart';

/// Hisably's signature screen — redesigned for clarity.
///
/// Step 1 — amount: close + currency on top, an In/Out segmented toggle,
/// the large centred amount (currency symbol inline), a round keypad and
/// one full-width action button that always states what will happen next.
/// The system keyboard is never shown.
///
/// Step 2 — details: amount summary, account, category, note, date, Save.
///
/// On success: restrained check animation + haptic, then the route pops and
/// returns the new transaction id so the caller can offer Undo.
class QuickAddScreen extends ConsumerStatefulWidget {
  const QuickAddScreen({super.key});

  @override
  ConsumerState<QuickAddScreen> createState() => _QuickAddScreenState();
}

class _QuickAddScreenState extends ConsumerState<QuickAddScreen> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(quickAddProvider);
    final s = context.spec;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [s.bgTop, s.bgBottom],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _TopBar(
                onClose: () => Navigator.of(context).maybePop(),
                currencyCode: state.currencyCode,
                onCurrencyChanged: (c) =>
                    ref.read(quickAddProvider.notifier).setCurrency(c),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: AppMotion.medium,
                  switchInCurve: AppMotion.enter,
                  switchOutCurve: AppMotion.exit,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.06),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  ),
                  child: state.step == QuickAddStep.amount
                      ? _AmountStep(key: const ValueKey('amount'))
                      : _DetailsStep(key: const ValueKey('details')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({
    required this.onClose,
    required this.currencyCode,
    required this.onCurrencyChanged,
  });

  final VoidCallback onClose;
  final String currencyCode;
  final ValueChanged<String> onCurrencyChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.spec;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          GlassIconButton(
            icon: Icons.close,
            tooltip: 'Close Quick Add',
            onPressed: onClose,
          ),
          const Spacer(),
          Text(
            'Quick Add',
            style: Theme.of(context)
                .textTheme
                .titleMedium!
                .copyWith(color: s.textSecondary),
          ),
          const Spacer(),
          CurrencySelectorChip(
            currencyCode: currencyCode,
            onChanged: onCurrencyChanged,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 1: amount
// ---------------------------------------------------------------------------

class _AmountStep extends ConsumerWidget {
  const _AmountStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(quickAddProvider);
    final controller = ref.read(quickAddProvider.notifier);
    final s = context.spec;

    final hasDirection = state.direction != null;
    final directionLabel = state.direction == TransactionType.income
        ? 'Income'
        : state.direction == TransactionType.expense
            ? 'Expense'
            : null;

    return Column(
      children: [
        const SizedBox(height: 10),
        // Direction toggle — explicit, colour-coded, haptic.
        _DirectionToggle(
          direction: state.direction,
          onPicked: controller.selectDirection,
          enabled: !state.saving,
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasDirection)
                  AnimatedSwitcher(
                    duration: AppMotion.fast,
                    child: Text(
                      directionLabel!,
                      key: ValueKey(directionLabel),
                      style: Theme.of(context).textTheme.labelLarge!.copyWith(
                            color: state.direction == TransactionType.income
                                ? s.income
                                : s.expense,
                            letterSpacing: 0.4,
                          ),
                    ),
                  )
                else
                  Text(
                    'Enter amount',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium!
                        .copyWith(color: s.textTertiary),
                  ),
                const SizedBox(height: 10),
                AmountDisplay(state: state),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26),
          child: KeypadGrid(
            onKey: controller.pressKey,
            onClear: controller.clearAmount,
            decimalEnabled: state.currency.decimalDigits > 0,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: _ContinueButton(state: state, onPressed: controller.proceedToDetails),
        ),
      ],
    );
  }
}

/// Two-segment In/Out selector. Selected segment is filled with its
/// semantic colour; unselected is glass — high contrast in every theme.
class _DirectionToggle extends StatelessWidget {
  const _DirectionToggle({
    required this.direction,
    required this.onPicked,
    required this.enabled,
  });

  final TransactionType? direction;
  final ValueChanged<TransactionType> onPicked;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final s = context.spec;
    Widget segment(String label, IconData icon, Color color,
        TransactionType type) {
      final selected = direction == type;
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          label: type == TransactionType.income
              ? 'Money received (In)'
              : 'Money spent (Out)',
          child: Material(
            color: selected
                ? color.withValues(alpha: s.isDark ? 0.28 : 0.16)
                : (s.isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.white.withValues(alpha: 0.6)),
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: enabled ? () => onPicked(type) : null,
              child: Container(
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: selected
                        ? color.withValues(alpha: 0.85)
                        : s.glassBorder,
                    width: selected ? 1.4 : 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: selected ? color : s.textSecondary, size: 20),
                    const SizedBox(width: 7),
                    Text(
                      label,
                      style: Theme.of(context).textTheme.titleMedium!.copyWith(
                            color: selected ? color : s.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          segment('In', Icons.south_west, s.income, TransactionType.income),
          const SizedBox(width: 10),
          segment('Out', Icons.north_east, s.expense, TransactionType.expense),
        ],
      ),
    );
  }
}

/// The single bottom action: always names the next step, disabled until the
/// amount parses AND a direction is picked.
class _ContinueButton extends StatelessWidget {
  const _ContinueButton({required this.state, required this.onPressed});

  final QuickAddState state;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final s = context.spec;
    final ready = state.canProceed && state.direction != null;
    final label = state.direction == null
        ? 'Pick In or Out to continue'
        : 'Continue · ${state.direction == TransactionType.income ? 'In' : 'Out'}'
            ' ${AmountFormat.money(state.amount!)}';

    return Semantics(
      button: true,
      enabled: ready,
      label: 'Continue to transaction details',
      child: Opacity(
        opacity: ready ? 1 : 0.5,
        child: Material(
          color: s.accent,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: ready ? onPressed : null,
            child: Container(
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: s.isDark
                      ? Colors.white.withValues(alpha: 0.16)
                      : Colors.white.withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium!.copyWith(
                      color: s.onAccent,
                      fontSize: 16,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 2: details
// ---------------------------------------------------------------------------

class _DetailsStep extends ConsumerStatefulWidget {
  const _DetailsStep({super.key});

  @override
  ConsumerState<_DetailsStep> createState() => _DetailsStepState();
}

class _DetailsStepState extends ConsumerState<_DetailsStep> {
  final _noteController = TextEditingController();
  bool _successOverlayVisible = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(quickAddProvider);
    final controller = ref.read(quickAddProvider.notifier);
    final s = context.spec;
    final accountsAsync = ref.watch(accountsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);

    final accounts = (accountsAsync.value ?? const <Account>[])
        .where((a) => a.currencyCode == state.currencyCode)
        .toList();
    final categories = (categoriesAsync.value ?? const <Category>[])
        .where((c) =>
            c.direction ==
            (state.direction == TransactionType.income
                ? CategoryDirection.inflow
                : CategoryDirection.outflow))
        .toList();

    final saving = state.saving;
    final canSave = state.accountId != null && !saving && !state.saved;
    final directionColor =
        state.direction == TransactionType.income ? s.income : s.expense;

    return Stack(
      children: [
        Column(
          children: [
            // Amount summary pill — direction-coloured, hard to misread.
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: directionColor.withValues(alpha: s.isDark ? 0.16 : 0.10),
                  border: Border.all(
                      color: directionColor.withValues(alpha: 0.45)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      state.direction == TransactionType.income
                          ? Icons.south_west
                          : Icons.north_east,
                      size: 18,
                      color: directionColor,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '${state.direction == TransactionType.income ? '+' : '-'}'
                        '${AmountFormat.money(state.amount ?? _zero(state.currencyCode))}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge!
                            .copyWith(
                              color: directionColor,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _SectionLabel('Account'),
                  if (accounts.isEmpty)
                    _NoAccountsHint(currencyCode: state.currencyCode)
                  else
                    _AccountChips(
                      accounts: accounts,
                      selectedId: state.accountId,
                      onSelect: controller.setAccount,
                    ),
                  const SizedBox(height: 18),
                  _SectionLabel('Category'),
                  _CategoryChips(
                    categories: categories,
                    selectedId: state.categoryId,
                    onSelect: controller.setCategory,
                  ),
                  const SizedBox(height: 18),
                  _SectionLabel('Note'),
                  TextField(
                    controller: _noteController,
                    textInputAction: TextInputAction.done,
                    maxLength: 120,
                    onChanged: controller.setNote,
                    style: TextStyle(color: s.textPrimary),
                    decoration: const InputDecoration(
                      hintText: 'Optional note',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 14),
                  _DateRow(
                    date: state.occurredAt ?? DateTime.now(),
                    onPicked: controller.setDate,
                  ),
                  const SizedBox(height: 22),
                ],
              ),
            ),
            // Back + Save
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Row(
                children: [
                  GlassIconButton(
                    icon: Icons.arrow_back,
                    tooltip: 'Back to amount',
                    onPressed: saving ? null : controller.backToAmount,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SaveButton(
                      enabled: canSave,
                      label: saving ? 'Saving…' : 'Save',
                      onPressed: () => _save(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (_successOverlayVisible || state.saved) const _SuccessOverlay(),
      ],
    );
  }

  static Money _zero(String code) => Money.zero(CurrencyRegistry.byCode(code));

  Future<void> _save() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final id = await ref.read(quickAddProvider.notifier).save();
    if (id == null) return;
    if (!mounted) return;
    AppHaptics.success();
    setState(() => _successOverlayVisible = true);
    // Give the success animation a beat, then hand the id back for Undo.
    await Future<void>.delayed(const Duration(milliseconds: 720));
    if (!mounted) return;
    Navigator.of(context).pop(id);
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final s = context.spec;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9, left: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .titleSmall!
              .copyWith(color: s.textSecondary),
        ),
      ),
    );
  }
}

class _NoAccountsHint extends ConsumerWidget {
  const _NoAccountsHint({required this.currencyCode});

  final String currencyCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.spec;
    return GlassPanel(
      blurred: false,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: s.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No $currencyCode account yet. Create one from the Accounts tab, then come back.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountChips extends StatelessWidget {
  const _AccountChips({
    required this.accounts,
    required this.selectedId,
    required this.onSelect,
  });

  final List<Account> accounts;
  final int? selectedId;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final a in accounts)
          _SelectableChip(
            label: a.name,
            icon: IconRegistry.forAccountKind(a.kind),
            selected: a.id == selectedId,
            semantic: 'Select account ${a.name}',
            onTap: () => onSelect(a.id),
          ),
      ],
    );
  }
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
    required this.categories,
    required this.selectedId,
    required this.onSelect,
  });

  final List<Category> categories;
  final int? selectedId;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in categories)
          _SelectableChip(
            label: c.name,
            icon: IconRegistry.forKey(c.iconKey),
            selected: c.id == selectedId,
            semantic: 'Select category ${c.name}',
            onTap: () => onSelect(c.id),
          ),
      ],
    );
  }
}

class _SelectableChip extends StatelessWidget {
  const _SelectableChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.semantic,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final String semantic;

  @override
  Widget build(BuildContext context) {
    final s = context.spec;
    final bg = selected
        ? s.accent.withValues(alpha: s.isDark ? 0.24 : 0.15)
        : s.isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.68);
    final border = selected
        ? s.accent.withValues(alpha: 0.8)
        : s.glassBorder;
    return Semantics(
      button: true,
      selected: selected,
      label: semantic,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            AppHaptics.tap();
            onTap();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 17,
                    color: selected ? s.accent : s.textSecondary),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium!.copyWith(
                        fontSize: 14,
                        color: selected ? s.accent : s.textPrimary,
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

class _DateRow extends ConsumerWidget {
  const _DateRow({required this.date, required this.onPicked});

  final DateTime date;
  final ValueChanged<DateTime> onPicked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.spec;
    final formatted = DateFormat('EEE, d MMM yyyy').format(date);
    return GlassPanel(
      blurred: false,
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: now.subtract(const Duration(days: 365)),
          lastDate: now,
        );
        if (picked != null) onPicked(picked);
      },
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Icon(Icons.event_outlined, size: 20, color: s.accent),
          const SizedBox(width: 12),
          Text(formatted, style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          Icon(
            Icons.expand_more,
            size: 20,
            color: s.textSecondary,
          ),
        ],
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({
    required this.enabled,
    required this.label,
    required this.onPressed,
  });

  final bool enabled;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final s = context.spec;
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Save transaction',
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Material(
          color: s.accent,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: enabled
                ? () {
                    AppHaptics.confirm();
                    onPressed();
                  }
                : null,
            child: Container(
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: s.isDark
                      ? Colors.white.withValues(alpha: 0.16)
                      : Colors.white.withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleMedium!.copyWith(
                      color: s.onAccent,
                      fontSize: 16.5,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Restrained success animation: a glass circle with a scaling check mark.
class _SuccessOverlay extends StatelessWidget {
  const _SuccessOverlay();

  @override
  Widget build(BuildContext context) {
    final s = context.spec;
    return Positioned.fill(
      child: Container(
        color: s.isDark
            ? Colors.black.withValues(alpha: 0.45)
            : Colors.white.withValues(alpha: 0.4),
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.5, end: 1),
            duration: AppMotion.medium,
            curve: Easing.emphasizedDecelerate,
            builder: (context, t, child) {
              return Opacity(
                opacity: t.clamp(0, 1),
                child: Transform.scale(scale: 0.7 + 0.3 * t, child: child),
              );
            },
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: s.income.withValues(alpha: 0.18),
                border: Border.all(color: s.income.withValues(alpha: 0.5)),
              ),
              child: Icon(Icons.check_rounded, color: s.income, size: 46),
            ),
          ),
        ),
      ),
    );
  }
}
