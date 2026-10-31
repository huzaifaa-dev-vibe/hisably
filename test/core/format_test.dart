import 'package:flutter_test/flutter_test.dart';
import 'package:hisably/core/money/currency.dart';
import 'package:hisably/core/money/money.dart';
import 'package:hisably/core/money/money_formatter.dart';

void main() {
  final usd = CurrencyRegistry.byCode('USD');
  final jpy = CurrencyRegistry.byCode('JPY');

  group('CurrencyRegistry', () {
    test('ISO precisions are explicit, never assumed', () {
      expect(CurrencyRegistry.byCode('JPY').decimalDigits, 0);
      expect(CurrencyRegistry.byCode('USD').decimalDigits, 2);
      expect(CurrencyRegistry.byCode('PKR').decimalDigits, 2);
      expect(CurrencyRegistry.byCode('BHD').decimalDigits, 3);
      expect(CurrencyRegistry.byCode('KWD').decimalDigits, 3);
    });

    test('unknown codes fall back to a 2-decimal generic', () {
      final c = CurrencyRegistry.byCode('XYZ');
      expect(c.decimalDigits, 2);
      expect(c.code, 'XYZ');
    });

    test('code validation', () {
      expect(CurrencyRegistry.isValidCode('USD'), isTrue);
      expect(CurrencyRegistry.isValidCode('usd'), isTrue); // case-insensitive
      expect(CurrencyRegistry.isValidCode('us'), isFalse); // must be 3 letters
      expect(CurrencyRegistry.isValidCode('USDD'), isFalse);
      expect(CurrencyRegistry.isValidCode('1\$2'), isFalse);
    });

    test('minor unit factors', () {
      expect(CurrencyRegistry.byCode('JPY').minorUnitFactor, 1);
      expect(CurrencyRegistry.byCode('USD').minorUnitFactor, 100);
      expect(CurrencyRegistry.byCode('BHD').minorUnitFactor, 1000);
    });
  });

  group('AmountFormat.typing — live keypad formatting', () {
    test('groups integer digits', () {
      expect(AmountFormat.typing('0', usd), '0');
      expect(AmountFormat.typing('1234567', usd), '1,234,567');
      expect(AmountFormat.typing('1234.5', usd), '1,234.5');
      expect(AmountFormat.typing('1234.', usd), '1,234.');
      expect(AmountFormat.typing('0.05', usd), '0.05');
      expect(AmountFormat.typing('', usd), '0');
    });

    test('0-decimal currency keeps integers ungrouped-safe', () {
      expect(AmountFormat.typing('123456', jpy), '123,456');
    });
  });

  group('AmountFormat.money', () {
    test('final display with symbol and fixed decimals', () {
      expect(AmountFormat.money(Money.fromMinor(123456, usd)), r'$ 1,234.56');
      expect(AmountFormat.money(Money.fromMinor(5, usd)), r'$ 0.05');
      expect(AmountFormat.money(Money.fromMinor(1234, jpy)), '¥ 1,234');
      expect(
        AmountFormat.money(Money.fromMinor(1234, usd), includeCode: true),
        r'$ 12.34 USD',
      );
    });
  });

  group('AmountFormat.ratio — exact integer long division', () {
    test('never loses precision to a double', () {
      expect(AmountFormat.ratio(1, 3, dp: 6), '0.333333');
      expect(AmountFormat.ratio(2, 3, dp: 6), '0.666666');
      expect(AmountFormat.ratio(10, 4, dp: 6), '2.500000');
      expect(AmountFormat.ratio(3, 7, dp: 9), '0.428571428');
      expect(AmountFormat.ratio(280, 70, dp: 4), '4.0000');
      expect(AmountFormat.ratio(-1, 4, dp: 2), '-0.25');
      expect(AmountFormat.ratio(1, 0, dp: 6), '—');
    });
  });
}
