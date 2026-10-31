import 'package:flutter/foundation.dart';

import 'currency.dart';

/// Maximum minor units Hisably accepts for a single amount:
/// 9,999,999,999,999 (≈ 10 trillion minor units). Well inside the 64-bit
/// signed range of both Dart `int` and SQLite INTEGER, and far beyond any
/// personal-finance use case.
const int kMaxMinorUnits = 9999999999999;

/// Maximum number of integer digits accepted from user input.
const int kMaxIntegerDigits = 12;

/// An exact monetary amount in a specific currency.
///
/// Money is stored as an **integer count of minor units** (cents, paisa,
/// fils…). Binary floating point is never used as an authoritative
/// representation. All arithmetic is integer arithmetic; overflow above
/// [kMaxMinorUnits] throws [MoneyOverflowException] rather than wrapping.
@immutable
class Money implements Comparable<Money> {
  const Money._(this.minorUnits, this.currency)
      : assert(minorUnits >= -kMaxMinorUnits,
            'negatives only via Money.fromSigned, within range');

  /// Creates a non-negative amount from minor units.
  factory Money.fromMinor(int minorUnits, Currency currency) {
    if (minorUnits < 0) {
      throw ArgumentError('minorUnits must be >= 0, got $minorUnits');
    }
    if (minorUnits > kMaxMinorUnits) {
      throw MoneyOverflowException(minorUnits);
    }
    return Money._(minorUnits, currency);
  }

  /// Zero amount in [currency].
  factory Money.zero(Currency currency) => Money._(0, currency);

  /// Creates an amount from minor units that may be negative.
  ///
  /// For **derived / display** values only — account balances and totals are
  /// aggregated from ledger rows and can legitimately be negative (e.g. an
  /// overdrawn cash account after exchange fees). User-entered transaction
  /// amounts must go through [Money.fromMinor] / [Money.parseRaw], which
  /// reject negatives.
  factory Money.fromSigned(int minorUnits, Currency currency) {
    if (minorUnits.abs() > kMaxMinorUnits) {
      throw MoneyOverflowException(minorUnits);
    }
    return Money._(minorUnits, currency);
  }

  final int minorUnits;
  final Currency currency;

  bool get isZero => minorUnits == 0;
  bool get isPositive => minorUnits > 0;

  /// Exact decimal string, e.g. "1234.5" (no grouping).
  String get decimalString => currency.minorToDecimalString(minorUnits);

  Money operator +(Money other) {
    _assertSameCurrency(other);
    final r = minorUnits + other.minorUnits;
    if (r > kMaxMinorUnits) throw MoneyOverflowException(r);
    return Money._(r, currency);
  }

  /// Returns [this] - [other]; result clamps at zero because balances in
  /// Hisably are always derived, never represented as signed Money inputs.
  Money operator -(Money other) {
    _assertSameCurrency(other);
    final r = minorUnits - other.minorUnits;
    return Money._(r < 0 ? 0 : r, currency);
  }

  /// True difference (may be needed for comparisons in UI).
  int deltaMinor(Money other) {
    _assertSameCurrency(other);
    return minorUnits - other.minorUnits;
  }

  void _assertSameCurrency(Money other) {
    if (other.currency != currency) {
      throw ArgumentError(
        'Currency mismatch: ${currency.code} vs ${other.currency.code}',
      );
    }
  }

  @override
  int compareTo(Money other) {
    _assertSameCurrency(other);
    return minorUnits.compareTo(other.minorUnits);
  }

  @override
  bool operator ==(Object other) =>
      other is Money && other.minorUnits == minorUnits && other.currency == currency;

  @override
  int get hashCode => Object.hash(minorUnits, currency);

  @override
  String toString() => 'Money(${currency.code} $decimalString)';

  /// Parses a user-typed raw string (digits with optional fraction, no
  /// separators, no sign) into exact minor units using pure string/integer
  /// math. Examples for a 2-digit currency:
  ///   "125"    -> 12500
  ///   "125.5"  -> 12550
  ///   "125.55" -> 12555
  ///   "0.05"   -> 5
  ///
  /// Throws [FormatException] when the string is malformed, has more
  /// fraction digits than the currency allows, or overflows.
  static Money parseRaw(String raw, Currency currency) {
    final s = raw.trim();
    if (s.isEmpty) throw const FormatException('empty amount');

    String intPart;
    String fracPart;
    final dot = s.indexOf('.');
    if (dot == -1) {
      intPart = s;
      fracPart = '';
    } else {
      if (s.indexOf('.', dot + 1) != -1) {
        throw FormatException('multiple decimal points: $raw');
      }
      intPart = s.substring(0, dot);
      fracPart = s.substring(dot + 1);
    }
    if (intPart.isEmpty) intPart = '0';

    if (!RegExp(r'^\d+$').hasMatch(intPart)) {
      throw FormatException('invalid integer part: $raw');
    }
    if (fracPart.isNotEmpty && !RegExp(r'^\d+$').hasMatch(fracPart)) {
      throw FormatException('invalid fraction part: $raw');
    }
    if (fracPart.length > currency.decimalDigits) {
      throw FormatException(
        '${currency.code} supports ${currency.decimalDigits} decimal '
        'digit(s); got "$fracPart"',
      );
    }
    if (intPart.length > kMaxIntegerDigits) {
      throw const FormatException('amount too large');
    }

    final factor = currency.minorUnitFactor;
    final frac = int.tryParse(fracPart.padRight(currency.decimalDigits, '0')) ?? 0;
    final major = int.parse(intPart);
    final minor = major * factor + frac;
    if (minor > kMaxMinorUnits) throw const FormatException('amount too large');
    return Money._(minor, currency);
  }

  /// Non-throwing variant of [parseRaw]; returns null on any error.
  static Money? tryParseRaw(String raw, Currency currency) {
    try {
      return parseRaw(raw, currency);
    } on FormatException {
      return null;
    }
  }
}

class MoneyOverflowException implements Exception {
  MoneyOverflowException(this.minorUnits);
  final int minorUnits;

  @override
  String toString() => 'MoneyOverflowException: $minorUnits exceeds supported range';
}
