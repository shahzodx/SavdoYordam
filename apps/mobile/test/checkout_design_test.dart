import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:savdoyordam/core/strings.dart';
import 'package:savdoyordam/design_system/forms.dart';
import 'package:savdoyordam/design_system/theme.dart';
import 'package:savdoyordam/features/pos/pos_screen.dart';

Widget host(Widget child, {double scale = 1}) => MaterialApp(
  key: UniqueKey(),
  theme: appTheme(),
  locale: const Locale('ru'),
  supportedLocales: const [Locale('ru'), Locale('uz')],
  localizationsDelegates: const [
    TestStringsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: Scaffold(body: child),
    ),
  ),
);
void main() {
  testWidgets(
    'credit explains why confirmation needs a customer; overpayment is visible',
    (tester) async {
      await tester.pumpWidget(
        host(const CheckoutSheet(total: 100000, customers: [])),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('В долг'));
      await tester.pumpAndSettle();
      expect(find.text('Выберите клиента для продажи в долг.'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.enterText(
        find.byKey(const ValueKey('checkout-paid')),
        '1001',
      );
      await tester.pumpAndSettle();
      expect(find.text('Введите сумму от 0 до итога продажи.'), findsWidgets);
      await tester.tap(find.text('Полностью'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'checkout remains usable at 200 percent text with the keyboard visible',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        host(const CheckoutSheet(total: 99999999999, customers: []), scale: 2),
      );
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getBottomRight(find.byType(FilledButton)).dy,
        lessThanOrEqualTo(520),
      );
    },
  );
  testWidgets('long product form keeps Save above keyboard on a small phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => appForm(context, 'addProduct', [
              for (var i = 0; i < 8; i++) FieldSpec('field-$i', 'name'),
            ]),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, 'Сохранить');
    expect(save, findsOneWidget);
    expect(tester.getBottomRight(save).dy, lessThanOrEqualTo(460));
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Заполните это поле'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

// Form behavior is independent of asynchronous asset loading; ARB loading is
// covered by localization_test. A synchronous delegate keeps fake-clock tests isolated.
class TestStringsDelegate extends LocalizationsDelegate<Strings> {
  const TestStringsDelegate();
  @override
  bool isSupported(Locale locale) => ['ru', 'uz'].contains(locale.languageCode);
  @override
  SynchronousFuture<Strings> load(Locale locale) => SynchronousFuture(
    Strings(
      locale,
      jsonDecode(
        File('lib/l10n/app_${locale.languageCode}.arb').readAsStringSync(),
      ) as Map<String, dynamic>,
    ),
  );
  @override
  bool shouldReload(TestStringsDelegate old) => false;
}
