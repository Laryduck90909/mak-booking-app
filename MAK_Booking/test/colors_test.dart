import 'package:flutter_test/flutter_test.dart';
import 'package:mak_booking/core/colors.dart';

void main() {
  test('HEX صالح وغير صالح', () {
    expect(parseColor('hex', '#0B3B3A'), isNotNull);
    expect(parseColor('hex', '0b3b3a'), isNotNull);
    expect(parseColor('hex', '#fff'), isNotNull);
    expect(parseColor('hex', '#12'), isNull);
    expect(parseColor('hex', 'zzzzzz'), isNull);
  });

  test('RGB', () {
    expect(parseColor('rgb', '11, 59, 58'), isNotNull);
    expect(parseColor('rgb', '300, 0, 0'), isNull);
    expect(parseColor('rgb', '1, 2'), isNull);
  });

  test('CMYK', () {
    final c = parseColor('cmyk', '0, 0, 0, 0');
    expect(c, isNotNull);
    expect(parseColor('cmyk', '0,0,0,101'), isNull);
    expect(parseColor('cmyk', '10,20,30'), isNull);
  });
}
