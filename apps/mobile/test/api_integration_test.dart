import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:savdoyordam/core/local_database.dart';
import 'package:savdoyordam/core/repository.dart';

void main() {
  const url = String.fromEnvironment('API_TEST_URL');
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Flutter repository → real Go API → PostgreSQL complete retail flow',
    () async {
      HttpOverrides.global = null;
      FlutterSecureStorage.setMockInitialValues({});
      final db = LocalDatabase(NativeDatabase.memory());
      final repo = Repository(
        db,
        const FlutterSecureStorage(),
        Dio(
          BaseOptions(
            baseUrl: url,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 30),
          ),
        ),
      );
      addTearDown(() async {
        await db.close();
        repo.dispose();
      });
      await repo.authenticate(
        'mobile-${DateTime.now().microsecondsSinceEpoch}@example.test',
        'integration-test-password',
        true,
      );
      await repo.createStore('Mobile integration test');
      final p = await repo.submit('/products', {
        'name': 'Olma',
        'sku': 'OLMA-1',
        'unit': 'kg',
        'price': 1200000,
        'cost': 800000,
        'stock': 5000,
        'minimum_stock': 1000,
      });
      final customer = await repo.submit('/customers', {
        'name': 'Test customer',
        'phone': '',
      });
      final sale = await repo.submit('/sales', {
        'customer_id': customer['id'],
        'paid': 500000,
        'method': 'cash',
        'items': [
          {'product_id': p['id'], 'quantity': 1500, 'expected_price': 1200000},
        ],
      });
      expect(sale['total'], 1800000);
      expect(sale['debt'], 1300000);
      final products = await repo.fetch('/products', paginated: true) as List;
      expect(products.single['id'], p['id']);
      expect(products.single['stock'], 3500);
      var dashboard = await repo.fetch('/dashboard') as Map;
      expect(dashboard['sales'], 1800000);
      expect(dashboard['received'], 500000);
      expect(dashboard['outstanding_debt'], 1300000);
      await repo.submit('/sales/${sale['id']}/payments', {
        'amount': 300000,
        'method': 'card',
      });
      dashboard = await repo.fetch('/dashboard') as Map;
      expect(dashboard['outstanding_debt'], 1000000);
      await repo.submit('/sales/${sale['id']}/return', {
        'reason': 'Integration test return',
      });
      dashboard = await repo.fetch('/dashboard') as Map;
      expect(dashboard['net_sales'], 0);
      expect(dashboard['received'], 0);
      expect(dashboard['outstanding_debt'], 0);
      expect(repo.queue, isEmpty);
      await repo.logout();
      expect(repo.authenticated, isFalse);
    },
    skip: url.isEmpty
        ? 'Set --dart-define=API_TEST_URL=http://127.0.0.1:18080 to run against a test server'
        : false,
  );
}
