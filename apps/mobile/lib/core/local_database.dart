import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

/// A small SQL-based Drift database. Money and command JSON retain integer values.
class LocalDatabase extends GeneratedDatabase {
  LocalDatabase(super.executor);
  static Future<LocalDatabase> open() async {
    final directory = await getApplicationSupportDirectory();
    return LocalDatabase(
      NativeDatabase.createInBackground(File('${directory.path}/savdo.sqlite')),
    );
  }

  @override
  int get schemaVersion => 2;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await customStatement(
        'CREATE TABLE cache (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at TEXT NOT NULL)',
      );
      await customStatement(
        "CREATE TABLE outbox (id TEXT PRIMARY KEY, actor TEXT NOT NULL, store TEXT NOT NULL, path TEXT NOT NULL, body TEXT NOT NULL, state TEXT NOT NULL DEFAULT 'pending', error TEXT, device TEXT NOT NULL DEFAULT '', lease TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL)",
      );
      await createCatalog();
      await customStatement(
        'CREATE INDEX outbox_actor ON outbox(actor,store,created_at)',
      );
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await customStatement(
          "ALTER TABLE outbox ADD COLUMN device TEXT NOT NULL DEFAULT ''",
        );
        await customStatement(
          "ALTER TABLE outbox ADD COLUMN lease TEXT NOT NULL DEFAULT ''",
        );
        await createCatalog();
      }
    },
  );
  Future<void> createCatalog() async {
    await customStatement(
      'CREATE TABLE catalog (namespace TEXT NOT NULL, id TEXT NOT NULL, name TEXT NOT NULL, sku TEXT NOT NULL, category TEXT NOT NULL, stock INTEGER NOT NULL, value TEXT NOT NULL, PRIMARY KEY(namespace,id))',
    );
    await customStatement(
      'CREATE INDEX catalog_search ON catalog(namespace,name,sku)',
    );
  }

  Future<void> replaceCatalog(String namespace, List rows) =>
      transaction(() async {
        await customStatement('DELETE FROM catalog WHERE namespace=?', [
          namespace,
        ]);
        for (final p in rows) {
          await customStatement(
            'INSERT INTO catalog(namespace,id,name,sku,category,stock,value) VALUES(?,?,?,?,?,?,?)',
            [
              namespace,
              p['id'],
              p['name'].toString().toLowerCase(),
              p['sku'].toString().toLowerCase(),
              p['category'] ?? '',
              p['stock'],
              jsonEncode(p),
            ],
          );
        }
      });
  Future<List<Map<String, dynamic>>> searchCatalog(
    String namespace,
    String query, {
    int limit = 60,
    int offset = 0,
    String? category,
    List<String>? ids,
  }) async {
    final pattern = query.trim().toLowerCase();
    return (await customSelect(
          "SELECT value FROM catalog WHERE namespace=? AND (instr(name,?)>0 OR instr(sku,?)>0) AND (?='' OR category=?) ${ids == null ? '' : 'AND id IN (${List.filled(ids.length, '?').join(',')})'} ORDER BY name,id LIMIT ? OFFSET ?",
          variables: [
            Variable(namespace),
            Variable(pattern),
            Variable(pattern),
            Variable(category ?? ''),
            Variable(category ?? ''),
            if (ids != null) ...ids.map(Variable.new),
            Variable(limit),
            Variable(offset),
          ],
        ).get())
        .map(
          (r) => Map<String, dynamic>.from(
            jsonDecode(r.read<String>('value')) as Map,
          ),
        )
        .toList();
  }

  Future<void> cache(String key, Object value) => customStatement(
    'INSERT OR REPLACE INTO cache(key,value,updated_at) VALUES(?,?,?)',
    [key, jsonEncode(value), DateTime.now().toUtc().toIso8601String()],
  );
  Future<Object?> cached(String key) async {
    final row = await customSelect(
      'SELECT value FROM cache WHERE key=?',
      variables: [Variable(key)],
    ).getSingleOrNull();
    return row == null ? null : jsonDecode(row.read<String>('value'));
  }

  Future<void> enqueue(
    String id,
    String actor,
    String store,
    String path,
    Map<String, dynamic> body, {
    String device = '',
    String lease = '',
  }) => customStatement(
    'INSERT INTO outbox(id,actor,store,path,body,device,lease,created_at) VALUES(?,?,?,?,?,?,?,?)',
    [
      id,
      actor,
      store,
      path,
      jsonEncode(body),
      device,
      lease,
      DateTime.now().toUtc().toIso8601String(),
    ],
  );
  Future<List<Map<String, dynamic>>> pending(
    String actor,
    String store,
  ) async => (await customSelect(
    'SELECT * FROM outbox WHERE actor=? AND store=? ORDER BY created_at,id',
    variables: [Variable(actor), Variable(store)],
  ).get()).map((r) => r.data).toList();
  Future<void> confirmed(String id) =>
      customStatement('DELETE FROM outbox WHERE id=?', [id]);
  Future<void> conflict(String id, String error) => customStatement(
    "UPDATE outbox SET state='conflict',error=? WHERE id=?",
    [error, id],
  );
  Future<void> dismissConflict(String id) => customStatement(
    "DELETE FROM outbox WHERE id=? AND state='conflict'",
    [id],
  );
}
