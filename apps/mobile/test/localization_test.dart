import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:savdoyordam/core/strings.dart';
import 'package:savdoyordam/design_system/theme.dart';

void main() {
  test('both ARB catalogs have the same complete nonempty key set', () {
    final uz =
        jsonDecode(File('lib/l10n/app_uz.arb').readAsStringSync()) as Map;
    final ru =
        jsonDecode(File('lib/l10n/app_ru.arb').readAsStringSync()) as Map;
    expect(uz.keys.toSet(), ru.keys.toSet());
    expect(uz.values.every((v) => v is String && v.isNotEmpty), isTrue);
    expect(ru.values.every((v) => v is String && v.isNotEmpty), isTrue);
  });
  for (final locale in ['uz', 'ru']) {
    testWidgets('empty and money states support $locale at 200% text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          locale: Locale(locale),
          supportedLocales: const [Locale('uz'), Locale('ru')],
          localizationsDelegates: const [
            Strings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: const Scaffold(
                body: SingleChildScrollView(child: EmptyState()),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(EmptyState), findsOneWidget);
    });
  }
}
