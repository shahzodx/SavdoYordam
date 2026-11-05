import 'package:flutter_test/flutter_test.dart';
import 'package:savdoyordam/core/amounts.dart';

void main() {
  test('money input never passes through a floating point number', () {
    expect(parseScaled('2 450 000,25', 2), 245000025);
    expect(parseScaled('0.01', 2), 1);
    expect(parseScaled('1.001', 2), isNull);
    expect(parseScaled('-1', 2), isNull);
    expect(parseSignedScaled('-0.25', 3), -250);
    expect(parseSignedScaled('1-2', 3), isNull);
    expect(quantity(-250), '-0.25');
    expect(quantity(-1250), '-1.25');
    expect(parseScaled('1e4', 2), isNull);
    expect(parseScaled('0.125', 3), 125);
    expect(lineTotal(101, 500), 51);
    expect(money(245000000, 'uz'), '2 450 000 so‘m');
    expect(money(-101, 'ru'), '−1,01 сум');
  });
}
