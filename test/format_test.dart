import 'package:devicemesh/core/utils/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatHms pads each part to two digits', () {
    expect(formatHms(DateTime(2026, 1, 1, 3, 4, 5)), '03:04:05');
  });

  test('shortId clips long IDs and keeps short ones', () {
    expect(shortId('1234567890'), '12345678');
    expect(shortId('abc'), 'abc');
  });
}