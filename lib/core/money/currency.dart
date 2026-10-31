import 'package:flutter/foundation.dart';

/// An ISO-4217 currency definition.
///
/// [decimalDigits] is the number of minor-unit digits defined by the ISO
/// standard (e.g. USD=2, JPY=0, BHD=3). Hisably never assumes a currency has
/// two decimals — every amount is stored as an integer count of minor units
/// and scaled by [minorUnitFactor].
@immutable
class Currency {
  const Currency({
    required this.code,
    required this.symbol,
    required this.decimalDigits,
    this.englishName,
  }) : assert(decimalDigits >= 0 && decimalDigits <= 3);

  /// ISO 4217 alphabetic code, exactly 3 characters.
  final String code;

  /// Display symbol (ASCII-friendly where a native glyph is impractical).
  final String symbol;

  /// Minor-unit digits per ISO 4217 (0, 1, 2 or 3).
  final int decimalDigits;

  final String? englishName;

  /// Multiplier that converts a major-unit amount into minor units.
  /// Computed without floating point.
  int get minorUnitFactor => switch (decimalDigits) {
        0 => 1,
        1 => 10,
        2 => 100,
        3 => 1000,
        _ => throw StateError('unreachable'),
      };

  /// Formats a count of minor units into its exact decimal string
  /// representation, e.g. (minor=123456, digits=2) -> "1234.56".
  String minorToDecimalString(int minor) {
    final neg = minor < 0;
    final m = minor.abs();
    final factor = minorUnitFactor;
    final major = m ~/ factor;
    final frac = m % factor;
    final buf = StringBuffer();
    if (neg) buf.write('-');
    buf.write(major);
    if (decimalDigits > 0) {
      buf.write('.');
      buf.write(frac.toString().padLeft(decimalDigits, '0'));
    }
    return buf.toString();
  }

  @override
  bool operator ==(Object other) => other is Currency && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'Currency($code)';
}

/// Curated registry of currencies Hisably supports out of the box.
///
/// Kept as explicit data (not generated) so precision is reviewable and
/// testable. Unknown 3-letter codes fall back to a 2-digit generic currency
/// so user-entered codes still work.
abstract final class CurrencyRegistry {
  static const Currency pkr = Currency(
    code: 'PKR',
    symbol: 'Rs',
    decimalDigits: 2,
    englishName: 'Pakistani Rupee',
  );

  static const List<Currency> all = [
    pkr,
    Currency(code: 'USD', symbol: r'$', decimalDigits: 2, englishName: 'US Dollar'),
    Currency(code: 'EUR', symbol: '€', decimalDigits: 2, englishName: 'Euro'),
    Currency(code: 'GBP', symbol: '£', decimalDigits: 2, englishName: 'British Pound'),
    Currency(code: 'INR', symbol: '₹', decimalDigits: 2, englishName: 'Indian Rupee'),
    Currency(code: 'AED', symbol: 'AED', decimalDigits: 2, englishName: 'UAE Dirham'),
    Currency(code: 'SAR', symbol: 'SAR', decimalDigits: 2, englishName: 'Saudi Riyal'),
    Currency(code: 'TRY', symbol: '₺', decimalDigits: 2, englishName: 'Turkish Lira'),
    Currency(code: 'BDT', symbol: '৳', decimalDigits: 2, englishName: 'Bangladeshi Taka'),
    Currency(code: 'LKR', symbol: 'Rs', decimalDigits: 2, englishName: 'Sri Lankan Rupee'),
    Currency(code: 'NPR', symbol: 'Rs', decimalDigits: 2, englishName: 'Nepalese Rupee'),
    Currency(code: 'AFN', symbol: 'Af', decimalDigits: 2, englishName: 'Afghan Afghani'),
    Currency(code: 'EGP', symbol: 'E£', decimalDigits: 2, englishName: 'Egyptian Pound'),
    Currency(code: 'JPY', symbol: '¥', decimalDigits: 0, englishName: 'Japanese Yen'),
    Currency(code: 'CNY', symbol: '¥', decimalDigits: 2, englishName: 'Chinese Yuan'),
    Currency(code: 'KRW', symbol: '₩', decimalDigits: 0, englishName: 'South Korean Won'),
    Currency(code: 'AUD', symbol: 'A\$', decimalDigits: 2, englishName: 'Australian Dollar'),
    Currency(code: 'CAD', symbol: 'C\$', decimalDigits: 2, englishName: 'Canadian Dollar'),
    Currency(code: 'CHF', symbol: 'CHF', decimalDigits: 2, englishName: 'Swiss Franc'),
    Currency(code: 'SGD', symbol: 'S\$', decimalDigits: 2, englishName: 'Singapore Dollar'),
    Currency(code: 'MYR', symbol: 'RM', decimalDigits: 2, englishName: 'Malaysian Ringgit'),
    Currency(code: 'IDR', symbol: 'Rp', decimalDigits: 2, englishName: 'Indonesian Rupiah'),
    Currency(code: 'THB', symbol: '฿', decimalDigits: 2, englishName: 'Thai Baht'),
    Currency(code: 'PHP', symbol: '₱', decimalDigits: 2, englishName: 'Philippine Peso'),
    Currency(code: 'VND', symbol: '₫', decimalDigits: 0, englishName: 'Vietnamese Dong'),
    Currency(code: 'NGN', symbol: '₦', decimalDigits: 2, englishName: 'Nigerian Naira'),
    Currency(code: 'KES', symbol: 'KSh', decimalDigits: 2, englishName: 'Kenyan Shilling'),
    Currency(code: 'TZS', symbol: 'TSh', decimalDigits: 2, englishName: 'Tanzanian Shilling'),
    Currency(code: 'UGX', symbol: 'USh', decimalDigits: 0, englishName: 'Ugandan Shilling'),
    Currency(code: 'ZAR', symbol: 'R', decimalDigits: 2, englishName: 'South African Rand'),
    Currency(code: 'BRL', symbol: r'R$', decimalDigits: 2, englishName: 'Brazilian Real'),
    Currency(code: 'MXN', symbol: r'$', decimalDigits: 2, englishName: 'Mexican Peso'),
    Currency(code: 'ARS', symbol: r'$', decimalDigits: 2, englishName: 'Argentine Peso'),
    Currency(code: 'CLP', symbol: r'$', decimalDigits: 0, englishName: 'Chilean Peso'),
    Currency(code: 'SEK', symbol: 'kr', decimalDigits: 2, englishName: 'Swedish Krona'),
    Currency(code: 'NOK', symbol: 'kr', decimalDigits: 2, englishName: 'Norwegian Krone'),
    Currency(code: 'DKK', symbol: 'kr', decimalDigits: 2, englishName: 'Danish Krone'),
    Currency(code: 'PLN', symbol: 'zł', decimalDigits: 2, englishName: 'Polish Zloty'),
    Currency(code: 'UAH', symbol: '₴', decimalDigits: 2, englishName: 'Ukrainian Hryvnia'),
    Currency(code: 'RUB', symbol: '₽', decimalDigits: 2, englishName: 'Russian Ruble'),
    // Zero/extra-precision currencies — exercised in rounding tests.
    Currency(code: 'KWD', symbol: 'KD', decimalDigits: 3, englishName: 'Kuwaiti Dinar'),
    Currency(code: 'BHD', symbol: 'BD', decimalDigits: 3, englishName: 'Bahraini Dinar'),
    Currency(code: 'OMR', symbol: 'OM', decimalDigits: 3, englishName: 'Omani Rial'),
    Currency(code: 'JOD', symbol: 'JD', decimalDigits: 3, englishName: 'Jordanian Dinar'),
    Currency(code: 'IQD', symbol: 'IQD', decimalDigits: 3, englishName: 'Iraqi Dinar'),
    Currency(code: 'TND', symbol: 'DT', decimalDigits: 3, englishName: 'Tunisian Dinar'),
    Currency(code: 'LYD', symbol: 'LD', decimalDigits: 3, englishName: 'Libyan Dinar'),
    Currency(code: 'QAR', symbol: 'QR', decimalDigits: 2, englishName: 'Qatari Riyal'),
  ];

  static Currency? tryByCode(String code) {
    for (final c in all) {
      if (c.code == code.toUpperCase()) return c;
    }
    return null;
  }

  /// Resolves [code] to a [Currency]; unknown codes get a generic
  /// 2-decimal definition with the code itself as symbol.
  static Currency byCode(String code) {
    return tryByCode(code) ??
        Currency(code: code.toUpperCase(), symbol: code.toUpperCase(), decimalDigits: 2);
  }

  static bool isValidCode(String code) =>
      code.length == 3 && RegExp(r'^[A-Za-z]{3}$').hasMatch(code);
}
