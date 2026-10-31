import 'package:flutter_test/flutter_test.dart';
import 'package:hisably/core/money/currency.dart';
import 'package:hisably/core/money/money.dart';
import 'package:hisably/core/money/money_formatter.dart';

void main() {
  final usd = CurrencyRegistry.byCode('USD'); // 2 decimals
  final jpy = CurrencyRegistry.byCode('JPY'); // 0 decimals
  final bhd = CurrencyRegistry.byCode('BHD'); // 3 decimals

  group('Money.parseRaw — exact integer math, no doubles', () {
    test('2-decimal currency', () {
      expect(Money.parseRaw('125', usd).minorUnits, 12500);
      expect(Money.parseRaw('125.5', usd).minorUnits, 12550);
      expect(Money.parseRaw('125.55', usd).minorUnits, 12555);
      expect(Money.parseRaw('0.05', usd).minorUnits, 5);
      expect(Money.parseRaw('0.', usd).minorUnits, 0);
    });

    test('0-decimal currency rejects fraction input', () {
      expect(Money.parseRaw('125', jpy).minorUnits, 125);
      expect(
        () => Money.parseRaw('125.5', jpy),
        throwsFormatException,
      );
    });

    test('3-decimal currency (BHD) preserves fils', () {
      expect(Money.parseRaw('1.234', bhd).minorUnits, 1234);
      expect(Money.parseRaw('0.001', bhd).minorUnits, 1);
      expect(
        () => Money.parseRaw('1.2345', bhd),
        throwsFormatException,
      );
    });

    test('rejects malformed input', () {
      expect(() => Money.parseRaw('12.3.4', usd), throwsFormatException);
      expect(() => Money.parseRaw('12a', usd), throwsFormatException);
      expect(() => Money.parseRaw('-5', usd), throwsFormatException);
      expect(() => Money.parseRaw('', usd), throwsFormatException);
      expect(() => Money.parseRaw('99999999999999', usd),
          throwsFormatException); // overflow
    });

    test('tryParseRaw returns null instead of throwing', () {
      expect(Money.tryParseRaw('12.3.4', usd), isNull);
      expect(Money.tryParseRaw('12.34', usd)?.minorUnits, 1234);
    });
  });

  group('Money arithmetic', () {
    test('add and subtract stay exact', () {
      final a = Money.parseRaw('10.10', usd);
      final b = Money.parseRaw('0.01', usd);
      expect((a + b).minorUnits, 1011);
      expect((a - b).minorUnits, 1009);
      expect((a - a).isZero, isTrue);
      expect(a.deltaMinor(b), 1009);
    });

    test('overflow throws instead of wrapping', () {
      expect(
        () => Money.fromMinor(kMaxMinorUnits + 1, usd),
        throwsA(isA<MoneyOverflowException>()),
      );
    });

    test('negative minor units rejected at construction', () {
      expect(() => Money.fromMinor(-1, usd), throwsArgumentError);
    });

    test('currency mismatch is an error', () {
      expect(() => Money.parseRaw('1', usd) + Money.parseRaw('1', jpy),
          throwsArgumentError);
    });
  });

  group('Money.fromSigned — derived/display amounts', () {
    test('accepts negative minor units for derived balances', () {
      final m = Money.fromSigned(-2500, usd);
      expect(m.minorUnits, -2500);
      expect(m.isZero, isFalse);
      expect(m.isPositive, isFalse);
    });

    test('accepts zero and positive too', () {
      expect(Money.fromSigned(0, usd).minorUnits, 0);
      expect(Money.fromSigned(12500, usd).minorUnits, 12500);
    });

    test('overflow still throws', () {
      expect(
        () => Money.fromSigned(-(kMaxMinorUnits + 1), usd),
        throwsA(isA<MoneyOverflowException>()),
      );
      expect(
        () => Money.fromSigned(kMaxMinorUnits + 1, usd),
        throwsA(isA<MoneyOverflowException>()),
      );
    });

    test('fromMinor still rejects negatives (input path unchanged)', () {
      expect(() => Money.fromMinor(-1, usd), throwsArgumentError);
    });
  });

  group('AmountFormat.money / compact — negative rendering', () {
    test('money renders a leading minus, keeps exact decimals', () {
      expect(AmountFormat.money(Money.fromSigned(-2500, usd)), r'-$ 25.00');
      expect(AmountFormat.money(Money.fromSigned(-5, usd)), r'-$ 0.05');
      expect(AmountFormat.money(Money.fromSigned(-1234, jpy)), '-¥ 1,234');
    });

    test('compact renders a leading minus, keeps symbol', () {
      expect(AmountFormat.compact(Money.fromSigned(-2500, usd)), r'-$ 25.00');
      expect(AmountFormat.compact(Money.fromMinor(2500, usd)), r'$ 25.00');
    });

    test('compact K/L/M scales with sign', () {
      expect(AmountFormat.compact(Money.fromSigned(-1234500, usd)), r'-$ 12.3K');
      expect(AmountFormat.compact(Money.fromMinor(1234567, usd)), r'$ 12.3K');
      expect(AmountFormat.compact(Money.fromMinor(12345678, usd)), r'$ 1.2L');
      expect(AmountFormat.compact(Money.fromMinor(12345678900, usd)), r'$ 12.3M');
    });
  });

  group('Currency.minorToDecimalString', () {
    test('round-trips minor units exactly', () {
      expect(usd.minorToDecimalString(123456), '1234.56');
      expect(usd.minorToDecimalString(5), '0.05');
      expect(usd.minorToDecimalString(-1234), '-12.34');
      expect(jpy.minorToDecimalString(1234), '1234');
      expect(bhd.minorToDecimalString(1234), '1.234');
    });
  });
}
