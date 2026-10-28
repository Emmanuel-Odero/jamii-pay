import 'package:flutter_test/flutter_test.dart';
import 'package:jamiipay/src/data/money_math.dart';
import 'package:jamiipay/src/data/pay_uri.dart';

void main() {
  group('MoneyMath.parseAmount', () {
    test('plain + decimals', () {
      expect(MoneyMath.parseAmount('10'), 10);
      expect(MoneyMath.parseAmount('10.50'), 10.5);
    });
    test('comma decimal + thousands', () {
      expect(MoneyMath.parseAmount('1,50'), 1.5);
      expect(MoneyMath.parseAmount('1,234.56'), 1234.56);
      expect(MoneyMath.parseAmount('1.234,56'), 1234.56);
    });
    test('rejects garbage / tiny / huge', () {
      expect(MoneyMath.parseAmount(''), isNull);
      expect(MoneyMath.parseAmount('abc'), isNull);
      expect(MoneyMath.parseAmount('0'), isNull);
      expect(MoneyMath.parseAmount('0.00001'), isNull);
      expect(MoneyMath.parseAmount('9999999'), isNull);
    });
  });

  group('MoneyMath mpesa', () {
    test('accepts +254/07/01 Safaricom ranges', () {
      expect(MoneyMath.isValidMpesaNumber('+254 722 000 000'), isTrue);
      expect(MoneyMath.isValidMpesaNumber('0722000000'), isTrue);
      expect(MoneyMath.isValidMpesaNumber('0112000000'), isTrue);
    });
    test('rejects short / non-mobile', () {
      expect(MoneyMath.isValidMpesaNumber('123'), isFalse);
      expect(MoneyMath.isValidMpesaNumber('+254 500 000 000'), isFalse);
    });
    test('formats to +254 xxx xxx xxx', () {
      expect(MoneyMath.formatMpesaNumber('0722000000'),
          '+254 722 000 000');
    });
  });

  group('parsePayUri', () {
    test('custom scheme + universal link', () {
      expect(parsePayUri('jamiipay://pay/amina5')?.fullHandle, 'amina5');
      expect(
          parsePayUri('https://jamiipay.com/pay/amina5?amount=10')
              ?.amountUsd,
          10);
    });
    test('tampered amount flagged, not silently dropped', () {
      final p = parsePayUri('jamiipay://pay/amina5?amount=abc');
      expect(p?.amountUsd, isNull);
      expect(p?.amountTampered, isTrue);
    });
    test('non-Jamii returns null', () {
      expect(parsePayUri('https://example.com'), isNull);
      expect(parsePayUri('WIFI:T:WPA;S:foo;;'), isNull);
    });
    test('builder lowercases/trims', () {
      expect(buildPayUri('  Amina5 '), 'jamiipay://pay/amina5');
    });
  });
}
