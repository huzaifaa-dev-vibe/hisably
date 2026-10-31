import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/haptics/app_haptics.dart';
import '../../core/money/currency.dart';
import '../../core/money/money.dart';
import '../providers.dart';
import '../repositories/exceptions.dart';

/// The two steps of the Quick Add flow.
enum QuickAddStep { amount, details }

/// Immutable state for the Quick Add flow.
class QuickAddState {
  const QuickAddState({
    this.raw = '0',
    required this.currencyCode,
    this.step = QuickAddStep.amount,
    this.direction,
    this.accountId,
    this.categoryId,
    this.note = '',
    this.occurredAt,
    this.saving = false,
    this.saved = false,
  });

  /// Raw keypad string ("0", "12", "12.", "12.5") — no separators.
  final String raw;
  final String currencyCode;
  final QuickAddStep step;

  /// Picked with the In / Out buttons. Null while on the amount step.
  final TransactionType? direction;

  final int? accountId;
  final int? categoryId;
  final String note;
  final DateTime? occurredAt;
  final bool saving;
  final bool saved;

  Currency get currency => CurrencyRegistry.byCode(currencyCode);

  /// Parsed amount; null when nothing meaningful typed yet.
  Money? get amount {
    final m = Money.tryParseRaw(raw, currency);
    return (m == null || m.isZero) ? null : m;
  }

  bool get canProceed => amount != null;

  QuickAddState copyWith({
    String? raw,
    String? currencyCode,
    QuickAddStep? step,
    TransactionType? direction,
    bool clearDirection = false,
    int? accountId,
    bool clearAccount = false,
    int? categoryId,
    bool clearCategory = false,
    String? note,
    DateTime? occurredAt,
    bool? saving,
    bool? saved,
  }) {
    return QuickAddState(
      raw: raw ?? this.raw,
      currencyCode: currencyCode ?? this.currencyCode,
      step: step ?? this.step,
      direction: clearDirection ? null : (direction ?? this.direction),
      accountId: clearAccount ? null : (accountId ?? this.accountId),
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      note: note ?? this.note,
      occurredAt: occurredAt ?? this.occurredAt,
      saving: saving ?? this.saving,
      saved: saved ?? this.saved,
    );
  }
}

/// Keypad key identifier.
enum QuickKey {
  digit0, digit1, digit2, digit3, digit4,
  digit5, digit6, digit7, digit8, digit9,
  decimal, backspace,
}

/// State machine + persistence for Quick Add.
///
/// Input model: the keypad appends digits/decimal to [QuickAddState.raw];
/// formatting is a pure view concern ([AmountFormat.typing]). The system
/// keyboard is never involved on the amount step.
class QuickAddController extends Notifier<QuickAddState> {
  @override
  QuickAddState build() {
    final code = ref.watch(primaryCurrencyProvider);
    return QuickAddState(currencyCode: code);
  }

  // ------------------------------------------------------------- keypad

  void pressKey(QuickKey key) {
    if (state.step != QuickAddStep.amount || state.saving) return;
    final cur = state.currency;
    var raw = state.raw;

    switch (key) {
      case QuickKey.backspace:
        if (raw.isNotEmpty) raw = raw.substring(0, raw.length - 1);
      case QuickKey.decimal:
        if (cur.decimalDigits == 0 || raw.contains('.')) return;
        raw = raw.isEmpty ? '0.' : '$raw.';
      case QuickKey.digit0:
        _appendDigit('0');
        return;
      case QuickKey.digit1:
        _appendDigit('1');
        return;
      case QuickKey.digit2:
        _appendDigit('2');
        return;
      case QuickKey.digit3:
        _appendDigit('3');
        return;
      case QuickKey.digit4:
        _appendDigit('4');
        return;
      case QuickKey.digit5:
        _appendDigit('5');
        return;
      case QuickKey.digit6:
        _appendDigit('6');
        return;
      case QuickKey.digit7:
        _appendDigit('7');
        return;
      case QuickKey.digit8:
        _appendDigit('8');
        return;
      case QuickKey.digit9:
        _appendDigit('9');
        return;
    }

    state = state.copyWith(raw: raw.isEmpty ? '0' : raw);
  }

  void _appendDigit(String d) {
    final raw = state.raw;
    final dot = raw.indexOf('.');
    if (dot != -1) {
      final fracLen = raw.length - dot - 1;
      if (fracLen >= state.currency.decimalDigits) return; // precision cap
      state = state.copyWith(raw: raw + d);
      return;
    }
    if (raw == '0') {
      // No leading zeros: leading 0 is replaced (0 stays 0).
      state = state.copyWith(raw: d);
      return;
    }
    if (raw.length >= kMaxIntegerDigits) return; // overflow cap
    state = state.copyWith(raw: raw + d);
  }

  void clearAmount() {
    if (state.step == QuickAddStep.amount && !state.saving) {
      state = state.copyWith(raw: '0');
    }
  }

  // --------------------------------------------------------------- flow

  void setCurrency(String code) {
    if (state.saving) return;
    if (code == state.currencyCode) return;
    // A different currency invalidates a previously picked account.
    state = state.copyWith(currencyCode: code, clearAccount: true);
  }

  /// Selects the direction while STAYING on the amount step (new UI: the
  /// In/Out toggle highlights, the user still taps Continue).
  void selectDirection(TransactionType type) {
    assert(type == TransactionType.income || type == TransactionType.expense);
    if (state.saving) return;
    state = state.copyWith(direction: type);
  }

  /// Moves to the details step. Requires a parsed amount and a direction.
  void proceedToDetails() {
    if (!state.canProceed || state.saving) return;
    if (state.direction == null) return;
    AppHaptics.confirm();
    state = state.copyWith(
      step: QuickAddStep.details,
      occurredAt: DateTime.now(),
      clearCategory: true,
    );
  }

  /// Legacy single-gesture path (set direction + advance). Kept for the
  /// widget tests and possible one-tap flows.
  void pickDirection(TransactionType type) {
    assert(type == TransactionType.income || type == TransactionType.expense);
    if (!state.canProceed || state.saving) return;
    AppHaptics.confirm();
    state = state.copyWith(
      direction: type,
      step: QuickAddStep.details,
      occurredAt: DateTime.now(),
      clearCategory: true,
    );
  }

  void setAccount(int id) {
    AppHaptics.tap();
    state = state.copyWith(accountId: id, clearCategory: true);
  }

  void setCategory(int id) {
    AppHaptics.tap();
    state = state.copyWith(categoryId: id);
  }

  void setNote(String value) => state = state.copyWith(note: value);

  void setDate(DateTime d) => state = state.copyWith(occurredAt: d);

  void backToAmount() {
    if (state.saving) return;
    state = state.copyWith(step: QuickAddStep.amount, clearDirection: true);
  }

  /// Persists the transaction. Returns the new ledger id, or null when the
  /// state is invalid. Guards duplicate submissions with the [saving] flag.
  Future<int?> save() async {
    final amount = state.amount;
    if (amount == null || state.saving || state.saved) return null;
    final account = state.accountId;
    if (account == null) return null;

    state = state.copyWith(saving: true);
    try {
      final repo = ref.read(transactionRepositoryProvider);
      final int id;
      final at = state.occurredAt ?? DateTime.now();
      final note = state.note.isEmpty ? null : state.note;
      if (state.direction == TransactionType.income) {
        id = await repo.addIncome(
          accountId: account,
          amountMinor: amount.minorUnits,
          categoryId: state.categoryId,
          note: note,
          occurredAt: at,
        );
      } else {
        id = await repo.addExpense(
          accountId: account,
          amountMinor: amount.minorUnits,
          categoryId: state.categoryId,
          note: note,
          occurredAt: at,
        );
      }
      state = state.copyWith(saving: false, saved: true);
      return id;
    } on DomainRuleException {
      AppHaptics.warn();
      state = state.copyWith(saving: false);
      return null;
    } catch (_) {
      AppHaptics.warn();
      state = state.copyWith(saving: false);
      return null;
    }
  }
}

final quickAddProvider = NotifierProvider<QuickAddController, QuickAddState>(
  QuickAddController.new,
);
