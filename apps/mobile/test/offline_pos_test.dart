import 'dart:io';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:savdoyordam/core/local_database.dart';
import 'package:savdoyordam/core/repository.dart';

class V1Database extends LocalDatabase {
  V1Database(super.executor);
  @override
  int get schemaVersion => 1;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await customStatement(
        'CREATE TABLE cache (key TEXT PRIMARY KEY,value TEXT NOT NULL,updated_at TEXT NOT NULL)',
      );
      await customStatement(
        "CREATE TABLE outbox (id TEXT PRIMARY KEY,actor TEXT NOT NULL,store TEXT NOT NULL,path TEXT NOT NULL,body TEXT NOT NULL,state TEXT NOT NULL DEFAULT 'pending',error TEXT,created_at TEXT NOT NULL)",
      );
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'v1 migration preserves an existing draft and pending command',
    () async {
      final dir = await Directory.systemTemp.createTemp('savdo-migration-');
      final file = File('${dir.path}/db.sqlite');
      final old = V1Database(NativeDatabase(file));
      await old.cache('one:shop:cart', [
        {'id': 'product', 'quantity': 1000},
      ]);
      await old.customStatement(
        "INSERT INTO outbox(id,actor,store,path,body,created_at) VALUES('key','one','shop','/sales','{}','2026-01-01')",
      );
      await old.close();
      final db = LocalDatabase(NativeDatabase(file));
      expect(await db.cached('one:shop:cart'), isNotEmpty);
      final pending = await db.pending('one', 'shop');
      expect(pending.single['id'], 'key');
      expect(pending.single['device'], '');
      expect(pending.single['lease'], '');
      await db.replaceCatalog('one:shop', [
        {
          'id': 'p',
          'name': 'Rice',
          'sku': 'R-1',
          'category': 'Food',
          'stock': 2000,
        },
      ]);
      expect((await db.searchCatalog('one:shop', 'R-1')).single['id'], 'p');
      expect(await db.searchCatalog('other:shop', ''), isEmpty);
      await db.close();
      await dir.delete(recursive: true);
    },
  );
  test('offline POS queues several sales, preserves stock and replays each UUID once after restart', () async {
    final dir = await Directory.systemTemp.createTemp('savdo-offline-pos-');
    final file = File('${dir.path}/db.sqlite');
    var db = LocalDatabase(NativeDatabase(file));
    var online = false;
    final applied = <String>{};
    final leases = <String>[];
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) {
            if (!online) {
              h.reject(
                DioException(
                  requestOptions: r,
                  type: DioExceptionType.connectionError,
                ),
              );
              return;
            }
            applied.add(r.headers['Idempotency-Key'] as String);
            leases.add(r.headers['X-Offline-Lease'] as String);
            h.resolve(
              Response(
                requestOptions: r,
                statusCode: 200,
                data: {'id': 'sale'},
              ),
            );
          },
        ),
      );
    var repo = Repository(db, const FlutterSecureStorage(), dio)
      ..actor = 'one'
      ..storeId = 'shop'
      ..deviceId = 'device';
    final lease = {
      'id': 'lease',
      'device_id': 'device',
      'actor_id': 'one',
      'server_time': DateTime.now().toUtc().toIso8601String(),
      'expires_at': DateTime.now()
          .toUtc()
          .add(const Duration(hours: 8))
          .toIso8601String(),
    };
    repo.offlineLease = lease;
    await db.cache('one:shop:/products', [
      {'id': 'p', 'name': 'Rice', 'sku': 'R-1', 'stock': 3000, 'price': 10000},
    ]);
    final body = {
      'paid': 10000,
      'method': 'cash',
      'items': [
        {'product_id': 'p', 'quantity': 1000, 'expected_price': 10000},
      ],
    };
    expect((await repo.submit('/sales', body))['queued'], true);
    expect((await repo.submit('/sales', body))['queued'], true);
    expect(repo.queue.length, 2);
    expect(repo.saleBlocked, false);
    expect(
      ((await db.cached('one:shop:/products')) as List).single['stock'],
      1000,
    );
    await expectLater(
      repo.submit('/sales', {
        'paid': 20000,
        'items': [
          {'product_id': 'p', 'quantity': 2000, 'expected_price': 10000},
        ],
      }),
      throwsA(isA<OperationFailure>()),
    );
    expect(repo.queue.length, 2);
    await db.close();
    repo.dispose();
    db = LocalDatabase(NativeDatabase(file));
    repo = Repository(db, const FlutterSecureStorage(), dio)
      ..actor = 'one'
      ..storeId = 'shop'
      ..deviceId = 'device'
      ..offlineLease = lease;
    await repo.readQueue();
    expect(repo.queue.length, 2);
    online = true;
    await repo.sync();
    await repo.sync();
    expect(repo.queue, isEmpty);
    expect(applied.length, 2);
    expect(leases, everyElement('lease'));
    expect(
      ((await db.cached('one:shop:/products')) as List).single['stock'],
      1000,
    );
    await db.close();
    repo.dispose();
    await dir.delete(recursive: true);
  });
  test(
    'a stale catalog response cannot overwrite projected offline stock',
    () async {
      final db = LocalDatabase(NativeDatabase.memory());
      final source = [
        {'id': 'p', 'name': 'Rice', 'sku': 'R', 'price': 10000, 'stock': 3000},
      ];
      final started = Completer<void>(), release = Completer<void>();
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (r, h) async {
              if (r.method == 'GET') {
                started.complete();
                await release.future;
                h.resolve(
                  Response(requestOptions: r, statusCode: 200, data: source),
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
        ..actor = 'one'
        ..storeId = 'shop'
        ..deviceId = 'device';
      repo.offlineLease = {
        'id': 'lease',
        'device_id': 'device',
        'actor_id': 'one',
        'server_time': DateTime.now().toUtc().toIso8601String(),
        'expires_at': DateTime.now()
            .toUtc()
            .add(const Duration(hours: 8))
            .toIso8601String(),
      };
      await db.cache('one:shop:/products', source);
      final fetch = repo.fetch('/products');
      await started.future;
      await repo.submit('/sales', {
        'paid': 10000,
        'items': [
          {'product_id': 'p', 'quantity': 1000, 'expected_price': 10000},
        ],
      });
      release.complete();
      expect((await fetch as List).single['stock'], 2000);
      expect((await db.searchCatalog('one:shop', '')).single['stock'], 2000);
      await db.close();
      repo.dispose();
    },
  );
  test('pagination remains bound to its original store while the selected store changes', () async {
    final db = LocalDatabase(NativeDatabase.memory());
    final paths = <String>[];
    late Repository repo;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) {
            paths.add(r.path);
            if (paths.length == 1) {
              repo.storeId = 'other-shop';
              h.resolve(
                Response(
                  requestOptions: r,
                  statusCode: 200,
                  data: List.generate(200, (i) => {'id': '$i'}),
                ),
              );
            } else {
              h.resolve(Response(requestOptions: r, statusCode: 200, data: []));
            }
          },
        ),
      );
    repo = Repository(db, const FlutterSecureStorage(), dio)
      ..actor = 'one'
      ..storeId = 'shop';
    await expectLater(
      repo.fetch('/sales', paginated: true),
      throwsA(isA<OperationFailure>()),
    );
    expect(paths, everyElement('/v1/stores/shop/sales'));
    expect(await db.cached('one:other-shop:/sales'), isNull);
    await db.close();
    repo.dispose();
  });
}
