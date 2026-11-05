import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:savdoyordam/app/app.dart';
import 'package:savdoyordam/app/providers.dart';
import 'package:savdoyordam/core/local_database.dart';
import 'package:savdoyordam/core/repository.dart';

// Explicit UI-test fixtures, never loaded by the production application.
const report = {
  'sales': 245000000,
  'received': 215000000,
  'outstanding_debt': 85000000,
  'sale_count': 24,
  'low_stock': 3,
  'net_sales': 245000000,
  'new_debt': 30000000,
  'repaid_debt': 0,
  'returns': 0,
  'expenses': 5000000,
  'gross_profit': 40000000,
};
const products = [
  {
    'id': '00000000-0000-4000-8000-000000000001',
    'name': 'Sut 1 L',
    'sku': 'SUT-1',
    'unit': 'piece',
    'price': 1400000,
    'cost': 1000000,
    'stock': 24000,
    'minimum_stock': 5000,
    'version': 1,
  },
  {
    'id': '00000000-0000-4000-8000-000000000002',
    'name': 'Guruch lazer',
    'sku': 'RICE-1',
    'unit': 'kg',
    'price': 1800000,
    'cost': 1200000,
    'stock': 12500,
    'minimum_stock': 3000,
    'version': 1,
  },
];
const customers = [
  {
    'id': 'customer-1',
    'name': 'Ali Karimov',
    'phone': '+998 90 123 45 67',
    'debt': 15000000,
  },
  {'id': 'customer-2', 'name': 'Dilnoza Akbarova', 'phone': '', 'debt': 0},
];
const sales = [
  {
    'id': 'sale-1',
    'customer_name': 'Ali Karimov',
    'customer_id': 'customer-1',
    'total': 5200000,
    'paid': 2200000,
    'returned_total': 0,
    'returned': false,
    'created_at': '2026-11-05T07:40:00Z',
  },
  {
    'id': 'sale-2',
    'customer_name': null,
    'total': 1400000,
    'paid': 1400000,
    'returned_total': 0,
    'returned': false,
    'created_at': '2026-11-05T06:20:00Z',
  },
];
Future<void> capture(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  if (!const bool.fromEnvironment('CAPTURE_PREVIEWS')) return;
  await tester.runAsync(() async {
    final picture =
        await (boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    final file = File('../../docs/previews/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    picture.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final language in ['uz', 'ru']) {
    testWidgets('five tabs, POS and settings work in $language', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final loader = FontLoader('NotoSans')
        ..addFont(rootBundle.load('assets/fonts/NotoSans.ttf'));
      await loader.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      final db = LocalDatabase(NativeDatabase.memory());
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (r, h) {
              if (r.method == 'GET' && r.path.endsWith('/customers')) {
                h.resolve(
                  Response(requestOptions: r, statusCode: 200, data: customers),
                );
              } else {
                h.reject(
                  DioException(
                    requestOptions: r,
                    type: DioExceptionType.connectionError,
                  ),
                );
              }
            },
          ),
        );
      final repo = Repository(db, const FlutterSecureStorage(), dio)
        ..actor = 'test'
        ..token = 'test'
        ..storeId = 'test'
        ..storeName = 'Baraka Market'
        ..language = language;
      addTearDown(() async {
        repo.dispose();
        await db.close();
      });
      final boundary = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(repo),
            dataProvider.overrideWith((ref, path) async {
              if (path == '/products') return products;
              if (path == '/customers') return customers;
              if (path == '/sales') return sales;
              if (path == '/offline') return {'active': false};
              if (path.startsWith('/analytics')) {
                return {
                  'daily': <Object>[],
                  'products': <Object>[],
                  'previous_net_sales': 0,
                };
              }
              if (path == '/dashboard' || path.startsWith('/reports')) {
                return report;
              }
              return <Object>[];
            }),
          ],
          child: RepaintBoundary(key: boundary, child: const SavdoApp()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Baraka Market'), findsOneWidget);
      if (const bool.fromEnvironment('CAPTURE_PREVIEWS')) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('../../docs/previews/dashboard_$language.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      final labels = language == 'uz'
          ? ['Savdolar', 'Mahsulotlar', 'Mijozlar', 'Hisobotlar']
          : ['Продажи', 'Товары', 'Клиенты', 'Отчёты'];
      for (final label in labels) {
        await tester.tap(
          find
              .descendant(
                of: find.byType(NavigationBar),
                matching: find.text(label),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture(
          tester,
          boundary,
          '${['sales', 'products', 'customers', 'reports'][labels.indexOf(label)]}_$language',
        );
      }
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.text('Guruch lazer'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, boundary, 'pos_$language');
      await tester.tap(find.text('Sut 1 L'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(language == 'uz' ? 'Savat · 1' : 'Корзина · 1').first,
      );
      await tester.pumpAndSettle();
      await capture(tester, boundary, 'cart_$language');
      await tester.tap(
        find.text(language == 'uz' ? 'To‘lovga o‘tish' : 'К оплате'),
      );
      await tester.pumpAndSettle();
      await capture(tester, boundary, 'checkout_$language');
      expect(tester.takeException(), isNull);
      await tester.tap(
        find.byTooltip(language == 'uz' ? 'Yopish' : 'Закрыть').last,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byTooltip(language == 'uz' ? 'Yopish' : 'Закрыть').last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text(language == 'uz' ? 'Maxfiylik' : 'Конфиденциальность'),
        350,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(
        find.text(language == 'uz' ? 'Maxfiylik' : 'Конфиденциальность'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
}
