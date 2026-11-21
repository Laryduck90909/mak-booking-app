import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mak_booking/shared/widgets/brand_logo.dart';

void main() {
  testWidgets('brand mark renders', (tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: BrandLogo())));
    expect(find.text('M.A.K'), findsOneWidget);
    expect(find.text('M'), findsOneWidget);
  });
}
