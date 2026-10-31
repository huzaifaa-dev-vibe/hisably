import 'package:intl/intl.dart';

import 'currency.dart';
import 'money.dart';

/// Locale-aware, floating-point-free formatting for amounts.
///
/// Grouping uses the current [Intl] locale's rules via
/// [NumberFormat.decimalPattern] applied to the *integer part only* — always
/// an exact `int`, never a double. Fraction digits are handled as strings.
abstract final class AmountFormat {
  static String _groupInteger(int value) {
    final NumberFormat nf = NumberFormat.decimalPattern(Intl.getCurrentLocale());
    return nf.format(value);
  }

  /// Canonical display for a final amount, e.g. "Rs 12,345.50".
  /// [includeCode] appends the ISO code when the symbol is ambiguous/empty.
  static String money(Money money, {bool includeCode = false}) {
    final c = money.currency;
    final neg = money.minorUnits < 0;
    final m = money.minorUnits.abs();
    final factor = c.minorUnitFactor;
    final major = m ~/ factor;
    final frac = m % factor;
    final buf = StringBuffer();
    if (neg) buf.write('-');
    if (c.symbol.isNotEmpty) buf.write('${c.symbol} ');
    buf.write(_groupInteger(major));
    if (c.decimalDigits > 0) {
      buf.write('.');
      buf.write(frac.toString().padLeft(c.decimalDigits, '0'));
    }
    if (includeCode || c.symbol.isEmpty) {
      buf.write(' ${c.code}');
    }
    return buf.toString();
  }

  /// Compact display for chips/rows, e.g. "Rs 1.2K", "Rs 34M".
  ///
  /// Conventions match [money]: symbol first, sign before the number.
  /// Grouping uses the South-Asian K/L/M convention (thousand / lakh /
  /// crore scale), which suits the app's primary audiences. Cosmetic only —
  /// never an authoritative representation.
  static String compact(Money money) {
    final c = money.currency;
    final m = money.minorUnits;
    final sign = m < 0 ? '-' : '';
    final symbol = c.symbol.isEmpty ? '' : '${c.symbol} ';
    final major = m.abs() ~/ c.minorUnitFactor;
    String? body;
    if (major >= 10000000) {
      body = '${_trim(major / 10000000)}M';
    } else if (major >= 100000) {
      body = '${_trim(major / 100000)}L';
    } else if (major >= 1000) {
      body = '${_trim(major / 1000)}K';
    }
    if (body == null) {
      return '$sign$symbol${Money.fromSigned(m.abs(), c).decimalString}';
    }
    return '$sign$symbol$body';
  }

  static String _trim(double d) {
    // Compact display is cosmetic only (never authoritative); one decimal.
    final s = d.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  /// Live formatting while the user types.
  ///
  /// [raw] is the un-normalised keypad string, e.g. "1234.5". Returns a
  /// grouped display string and preserves an in-progress trailing dot, e.g.
  /// "1,234.5" / "1,234." / "0.05".
  static String typing(String raw, Currency currency) {
    if (raw.isEmpty) return '0';
    final dot = raw.indexOf('.');
    final hasDot = dot != -1;
    var intPart = hasDot ? raw.substring(0, dot) : raw;
    final fracPart = hasDot ? raw.substring(dot + 1) : '';
    if (intPart.isEmpty) intPart = '0';

    final grouped = _groupInteger(int.tryParse(intPart) ?? 0);
    final buf = StringBuffer(grouped);
    if (hasDot) {
      buf.write('.');
      buf.write(fracPart);
    }
    return buf.toString();
  }

  /// Exact rational ratio of [numerator]/[denominator] rendered with [dp]
  /// decimal places using pure integer long division — used for effective
  /// exchange rates so no float ever touches stored values.
  static String ratio(int numerator, int denominator, {int dp = 6}) {
    if (denominator == 0) return '—';
    final neg = (numerator < 0) != (denominator < 0);
    final n = numerator.abs();
    final d = denominator.abs();
    final intPart = n ~/ d;
    var rem = n % d;
    final StringBuffer buf = StringBuffer();
    if (neg) buf.write('-');
    buf.write(intPart);
    if (dp > 0) {
      buf.write('.');
      for (var i = 0; i < dp; i++) {
        rem *= 10;
        final digit = rem ~/ d;
        buf.write(digit);
        rem %= d;
      }
    }
    return buf.toString();
  }
}
