import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mak_booking/core/localization/app_localizations.dart';
import 'package:mak_booking/core/theme/app_theme.dart';
import 'package:mak_booking/features/requests/request_wizard_screen.dart';

Future<void> pumpWizardAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.dark.copyWith(splashFactory: NoSplash.splashFactory),
        home: const RequestWizardScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  expect(find.byType(Checkbox), findsWidgets);
  await tester.tap(find.byType(Checkbox).first);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  await tester.tap(find.text('التالي'));
  await tester.pumpAndSettle();
  expect(find.text('68', findRichText: true), findsNothing);
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('wizard works on phone and wide desktop', (tester) async {
    await pumpWizardAt(tester, const Size(375, 812));
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpWizardAt(tester, const Size(1100, 800));
  });
}
