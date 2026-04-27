import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lgu_mobile/screens/qr_scanner_screen.dart';

void main() {
  test('QrScannerScreen can be constructed', () {
    expect(const QrScannerScreen(), isA<Widget>());
  });
}
