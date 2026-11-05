import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:savdoyordam/core/local_database.dart';
import 'package:savdoyordam/core/repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'lost response survives restart and retries the exact key and payload',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final directory = await Directory.systemTemp.createTemp('savdo-outbox-');
      final file = File('${directory.path}/test.sqlite');
      var db = LocalDatabase(NativeDatabase(file));
      final dio = Dio();
      final keys = <String>[];
      final payloads = <Object?>[];
      var writes = 0;
      final applied = <String>{};
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            final key = request.headers['Idempotency-Key'] as String;
            keys.add(key);
            payloads.add(request.data);
            if (applied.add(key)) writes++;
            if (keys.length == 1) {
              handler.reject(
                DioException(
                  requestOptions: request,
                  type: DioExceptionType.receiveTimeout,
                ),
              );
            } else {
              handler.resolve(
                Response(
                  requestOptions: request,
                  statusCode: 200,
                  data: {'id': 'sale-1', 'total': 10000},
                ),
              );
            }
          },
        ),
      );
      var repo = Repository(db, const FlutterSecureStorage(), dio)
        ..actor = 'user-a'
        ..storeId = 'store-a'
        ..token = 'session';
      await db.cache('user-a:store-a:cart', [
        {'id': 'product'},
      ]);
      await expectLater(
        repo.submit('/sales', {'paid': 10000, 'items': []}),
        throwsA(isA<OperationFailure>()),
      );
      expect(repo.queue.length, 1);
      expect(repo.saleBlocked, isTrue);
      expect(await db.cached('user-a:store-a:cart'), isEmpty);
      await db.close();
      repo.dispose();
      db = LocalDatabase(NativeDatabase(file));
      repo = Repository(db, const FlutterSecureStorage(), dio)
        ..actor = 'user-a'
        ..storeId = 'store-a'
        ..token = 'session';
      await repo.readQueue();
      expect(repo.queue.length, 1);
      await repo.sync();
      expect(repo.queue, isEmpty);
      expect(keys[0], keys[1]);
      expect(payloads[0], payloads[1]);
      expect(writes, 1);
      await db.close();
      repo.dispose();
      await directory.delete(recursive: true);
    },
  );
  test(
    'definitive rejection is retained, tenant queues remain isolated',
    () async {
      final db = LocalDatabase(NativeDatabase.memory());
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) => h.reject(
            DioException(
              requestOptions: r,
              response: Response(
                requestOptions: r,
                statusCode: 409,
                data: {'error': 'insufficient_stock'},
              ),
            ),
          ),
        ),
      );
      final repo = Repository(db, const FlutterSecureStorage(), dio)
        ..actor = 'one'
        ..storeId = 'shop';
      await expectLater(
        repo.submit('/sales', {'paid': 0}),
        throwsA(isA<OperationFailure>()),
      );
      expect(repo.queue.single['state'], 'conflict');
      final id = repo.queue.single['id'] as String;
      repo.actor = 'two';
      await repo.readQueue();
      expect(repo.queue, isEmpty);
      repo.actor = 'one';
      await repo.readQueue();
      await repo.sync();
      expect(repo.queue.length, 1);
      await repo.dismiss(id);
      expect(repo.queue, isEmpty);
      await db.close();
      repo.dispose();
    },
  );
  test('cached catalog is readable when the network fails', () async {
    final db = LocalDatabase(NativeDatabase.memory());
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (r, h) => h.reject(
          DioException(
            requestOptions: r,
            type: DioExceptionType.connectionError,
          ),
        ),
      ),
    );
    final repo = Repository(db, const FlutterSecureStorage(), dio)
      ..actor = 'one'
      ..storeId = 'shop';
    await db.cache('one:shop:/products', [
      {'id': 'p', 'stock': 1000},
    ]);
    expect(await repo.fetch('/products'), [
      {'id': 'p', 'stock': 1000},
    ]);
    expect(repo.offline, isTrue);
    await db.close();
    repo.dispose();
  });
}
