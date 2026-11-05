import 'dart:convert';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import 'local_database.dart';
import 'stock_notifications.dart';

class OperationFailure implements Exception {
  const OperationFailure(this.code);
  final String code;
}

class Repository extends ChangeNotifier {
  Repository(this.db, this.secure, this.dio);
  final LocalDatabase db;
  final FlutterSecureStorage secure;
  final Dio dio;
  String? actor, token, storeId;
  String storeName = '';
  String language = 'uz', role = 'owner';
  String deviceId = const Uuid().v4();
  Map<String, dynamic>? offlineLease;
  Set<String> favorites = {};
  List<String> recentProducts = [];
  bool notificationsEnabled = false;
  Future<void> loadPreferences() async {
    final f = await db.cached('$namespace:favorites');
    favorites = f is List ? f.cast<String>().toSet() : {};
    final r = await db.cached('$namespace:recent_products');
    recentProducts = r is List ? r.cast<String>() : [];
  }

  Future<void> toggleFavorite(String id) async {
    if (!favorites.remove(id)) favorites.add(id);
    await db.cache('$namespace:favorites', favorites.toList());
    notifyListeners();
  }

  Future<void> rememberProducts(List items) async {
    recentProducts = {
      ...items.map((i) => i['product_id'] as String),
      ...recentProducts,
    }.take(30).toList();
    await db.cache('$namespace:recent_products', recentProducts);
    notifyListeners();
  }

  bool get isOwner => role == 'owner';
  bool get offlineEnabled {
    final lease = offlineLease;
    if (lease == null ||
        lease['device_id'] != deviceId ||
        lease['actor_id'] != actor) {
      return false;
    }
    final now = DateTime.now().toUtc();
    final expires = DateTime.tryParse(lease['expires_at'] ?? '');
    final issued = DateTime.tryParse(lease['server_time'] ?? '');
    return expires != null &&
        issued != null &&
        now.isBefore(expires) &&
        !now.isBefore(issued.subtract(const Duration(minutes: 5)));
  }

  bool offline = false, syncing = false;
  Timer? _retryTimer;
  int _retryAttempt = 0;
  bool _foreground = true;
  void pauseSync() {
    _foreground = false;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  Future<void> resumeSync() async {
    _foreground = true;
    await sync();
  }

  void scheduleRetry() {
    if (!_foreground || _retryTimer?.isActive == true) return;
    final seconds = (2 * (1 << _retryAttempt.clamp(0, 5))).clamp(2, 60);
    _retryAttempt++;
    _retryTimer = Timer(Duration(seconds: seconds), () {
      _retryTimer = null;
      if (_foreground) sync();
    });
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  List<Map<String, dynamic>> queue = [];
  bool get authenticated => token != null;
  bool get hasStore => storeId != null;
  bool get saleBlocked =>
      queue.any((q) => q['state'] == 'conflict') ||
      (!offlineEnabled &&
          queue.any((q) => q['path'].toString().endsWith('/sales')));
  String get base => '/v1/stores/$storeId';
  String get namespace => '$actor:$storeId';
  Future<void> restore() async {
    language = await secure.read(key: 'language') ?? 'uz';
    deviceId = await secure.read(key: 'device_id') ?? deviceId;
    await secure.write(key: 'device_id', value: deviceId);
    notificationsEnabled =
        await secure.read(key: 'stock_notifications') == 'true';
    final session = await secure.read(key: 'session');
    if (session != null) {
      final s = jsonDecode(session) as Map<String, dynamic>;
      actor = s['actor'];
      token = s['token'];
      storeId = s['store_id'];
      storeName = s['store_name'] ?? '';
      role = s['role'] ?? 'owner';
    }
    dio.options.headers['Authorization'] = 'Bearer $token';
    await readQueue();
    await loadPreferences();
    final lease = await db.cached('$namespace:offline_lease');
    offlineLease = lease is Map ? Map<String, dynamic>.from(lease) : null;
  }

  Future<void> saveSession() => secure.write(
    key: 'session',
    value: jsonEncode({
      'actor': actor,
      'token': token,
      'store_id': storeId,
      'store_name': storeName,
      'role': role,
    }),
  );
  Future<void> setLanguage(String value) async {
    language = value;
    await secure.write(key: 'language', value: value);
    notifyListeners();
  }

  Future<void> authenticate(
    String email,
    String password,
    bool register,
  ) async {
    try {
      final response = await dio.post(
        '/v1/auth/${register ? 'register' : 'login'}',
        data: {'email': email, 'password': password},
      );
      final data = response.data as Map<String, dynamic>;
      if (actor != null && actor != data['user_id'] && queue.isNotEmpty) {
        throw const OperationFailure('pending_operations');
      }
      actor = data['user_id'];
      token = data['token'];
      dio.options.headers['Authorization'] = 'Bearer $token';
      storeId = null;
      storeName = '';
      await saveSession();
      final stores = (await dio.get('/v1/stores')).data as List;
      if (stores.isNotEmpty) {
        storeId = stores.first['id'];
        storeName = stores.first['name'];
        role = stores.first['role'] ?? 'cashier';
      }
      await saveSession();
      await readQueue();
      await loadPreferences();
      final lease = await db.cached('$namespace:offline_lease');
      offlineLease = lease is Map ? Map<String, dynamic>.from(lease) : null;
      notifyListeners();
    } on DioException catch (e) {
      throw OperationFailure(errorCode(e));
    }
  }

  Future<void> createStore(String name, {String retailType = 'general'}) async {
    final key = 'onboarding:$actor';
    final old = await db.cached(key);
    final command = old is Map
        ? Map<String, dynamic>.from(old)
        : {'id': const Uuid().v4(), 'name': name, 'retail_type': retailType};
    if (command['name'] != name) {
      throw const OperationFailure('onboarding_pending');
    }
    await db.cache(key, command);
    try {
      final result = (await dio.post('/v1/stores', data: command)).data;
      storeId = result['id'];
      storeName = result['name'];
      role = result['role'] ?? 'owner';
      offlineLease = null;
      await loadPreferences();
      await db.customStatement('DELETE FROM cache WHERE key=?', [key]);
      await saveSession();
      await readQueue();
      notifyListeners();
    } on DioException catch (e) {
      throw OperationFailure(errorCode(e));
    }
  }

  Future<void> logout() async {
    if (offlineEnabled) throw const OperationFailure('offline_store_locked');
    if (queue.isNotEmpty) throw const OperationFailure('pending_operations');
    try {
      if (notificationsEnabled) await StockNotifications.cancel();
      await dio.post(
        '/v1/auth/logout',
        options: Options(headers: {'X-Device-ID': deviceId}),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode != 401) throw OperationFailure(errorCode(e));
    }
    await secure.delete(key: 'session');
    token = null;
    actor = null;
    storeId = null;
    storeName = '';
    queue = [];
    offlineLease = null;
    dio.options.headers.remove('Authorization');
    notifyListeners();
  }

  String errorCode(DioException e) {
    if (e.response?.data is Map) {
      return e.response!.data['error']?.toString() ?? 'server_error';
    }
    return 'connection_error';
  }

  Future<Object> fetch(String path, {bool paginated = false}) async {
    final requestNamespace = namespace, requestBase = base;
    final requestActor = actor, requestStore = storeId;
    final key = '$requestNamespace:$path';
    if (path == '/products' &&
        queue.any((q) => q['path'].toString().endsWith('/sales'))) {
      final projected = await db.cached(key);
      if (projected != null) return projected;
    }
    try {
      Object result;
      if (paginated) {
        final all = <dynamic>[];
        int offset = 0;
        while (true) {
          final data =
              (await dio.get(
                    '$requestBase$path',
                    queryParameters: {'limit': 200, 'offset': offset},
                  )).data
                  as List;
          all.addAll(data);
          if (data.length < 200) break;
          offset += 200;
        }
        result = all;
      } else {
        result = (await dio.get('$requestBase$path')).data as Object;
      }
      if (namespace != requestNamespace) {
        throw const OperationFailure('store_changed');
      }
      await db.transaction(() async {
        if (path == '/products' &&
            requestActor != null &&
            requestStore != null) {
          final pending = await db.pending(requestActor, requestStore);
          if (pending.any((q) => q['path'].toString().endsWith('/sales'))) {
            final projected = await db.cached(key);
            if (projected != null) {
              result = projected;
              return;
            }
          }
        }
        await db.cache(key, result);
        if (path == '/products' && result is List) {
          await db.replaceCatalog(requestNamespace, result as List);
        }
      });
      offline = false;
      return result;
    } on DioException catch (e) {
      if (namespace != requestNamespace) {
        throw const OperationFailure('store_changed');
      }
      if (e.response?.statusCode == 401 ||
          e.response?.statusCode == 403 ||
          e.response?.statusCode == 404) {
        throw OperationFailure(errorCode(e));
      }
      offline = true;
      final cache = await db.cached(key);
      if (cache != null) return cache;
      throw OperationFailure(errorCode(e));
    } finally {
      notifyListeners();
    }
  }

  Future<void> readQueue() async {
    queue = actor != null && storeId != null
        ? await db.pending(actor!, storeId!)
        : [];
  }

  Future<Map<String, dynamic>> submit(
    String path,
    Map<String, dynamic> body,
  ) async {
    if (actor == null || storeId == null) {
      throw const OperationFailure('unauthorized');
    }
    if (queue.isNotEmpty &&
        !(path == '/sales' &&
            offlineEnabled &&
            !saleBlocked &&
            queue.every(
              (q) =>
                  q['state'] == 'pending' &&
                  q['path'].toString().endsWith('/sales'),
            ))) {
      throw const OperationFailure('pending_operations');
    }
    if (path == '/sales' && saleBlocked) {
      throw const OperationFailure('pending_operations');
    }
    if (path == '/sales' && offlineEnabled) {
      body = {...body, 'occurred_at': DateTime.now().toUtc().toIso8601String()};
    }
    final id = const Uuid().v4();
    await db.transaction(() async {
      if (path == '/sales' && offlineEnabled) {
        final rows = await db.cached('$namespace:/products');
        if (rows is! List) {
          throw const OperationFailure('offline_catalog_required');
        }
        final updated = rows
            .map((p) => Map<String, dynamic>.from(p as Map))
            .toList();
        for (final item in body['items'] as List) {
          final index = updated.indexWhere(
            (p) => p['id'] == item['product_id'],
          );
          if (index < 0 || updated[index]['stock'] < item['quantity']) {
            throw const OperationFailure('insufficient_stock');
          }
          if (updated[index]['price'] != item['expected_price']) {
            throw const OperationFailure('price_changed');
          }
          updated[index]['stock'] =
              (updated[index]['stock'] as int) - (item['quantity'] as int);
        }
        await db.cache('$namespace:/products', updated);
        await db.replaceCatalog(namespace, updated);
      }
      await db.enqueue(
        id,
        actor!,
        storeId!,
        '$base$path',
        body,
        device: deviceId,
        lease: path == '/sales' && offlineEnabled
            ? offlineLease!['id'] as String
            : '',
      );
      if (path == '/sales') await db.cache('$namespace:cart', []);
    });
    await readQueue();
    notifyListeners();
    try {
      return await send(queue.firstWhere((q) => q['id'] == id));
    } on OperationFailure catch (e) {
      if (path == '/sales' && offlineEnabled && e.code == 'operation_pending') {
        return {'queued': true, 'command_id': id};
      }
      rethrow;
    }
  }

  final Set<String> _sending = {};
  Future<Map<String, dynamic>> send(
    Map<String, dynamic> command, {
    String? resolution,
  }) async {
    final id = command['id'] as String;
    if (command['actor'] != actor ||
        command['store'] != storeId ||
        _sending.contains(id)) {
      throw const OperationFailure('pending_operations');
    }
    _sending.add(id);
    try {
      final response = await dio.post(
        command['path'] as String,
        data: jsonDecode(command['body'] as String),
        options: Options(
          headers: {
            'Idempotency-Key': id,
            'X-Device-ID': command['device'] ?? deviceId,
            'X-Offline-Resolution': ?resolution,
            if ((command['lease'] ?? '').isNotEmpty)
              'X-Offline-Lease': command['lease'],
          },
        ),
      );
      if (command['path'].toString().endsWith('/offline/enable')) {
        offlineLease = Map<String, dynamic>.from(response.data as Map);
        await db.cache('$namespace:offline_lease', offlineLease!);
      } else if (command['path'].toString().endsWith('/offline/disable')) {
        offlineLease = null;
        await db.cache('$namespace:offline_lease', {});
      }
      if (command['path'].toString().endsWith('/settings')) {
        storeName = response.data['name'];
        await saveSession();
      }
      await db.confirmed(id);
      offline = false;
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final code = errorCode(e);
      if (status != null && [400, 403, 404, 409, 422].contains(status)) {
        await db.conflict(id, code);
        throw OperationFailure(code);
      }
      offline = status == null || status >= 500;
      if (offline) scheduleRetry();
      throw OperationFailure(
        status == 401 ? 'unauthorized' : 'operation_pending',
      );
    } finally {
      _sending.remove(id);
      await readQueue();
      notifyListeners();
    }
  }

  Future<void> sync() async {
    if (syncing) return;
    syncing = true;
    notifyListeners();
    try {
      await readQueue();
      for (final command in List<Map<String, dynamic>>.from(queue)) {
        if (command['state'] == 'conflict') break;
        if (command['state'] == 'pending') {
          try {
            await send(command);
          } on OperationFailure {
            break;
          }
        }
      }
    } finally {
      syncing = false;
      if (queue.isEmpty) {
        _retryAttempt = 0;
        _retryTimer?.cancel();
        _retryTimer = null;
      }
      notifyListeners();
    }
  }

  Future<List<Map<String, dynamic>>> availableStores() async {
    try {
      return ((await dio.get('/v1/stores')).data as List)
          .map((s) => Map<String, dynamic>.from(s as Map))
          .toList();
    } on DioException catch (e) {
      throw OperationFailure(errorCode(e));
    }
  }

  Future<void> switchStore(Map<String, dynamic> store) async {
    if (queue.isNotEmpty) throw const OperationFailure('pending_operations');
    storeId = store['id'];
    storeName = store['name'];
    role = store['role'] ?? 'cashier';
    await saveSession();
    await readQueue();
    await loadPreferences();
    final lease = await db.cached('$namespace:offline_lease');
    offlineLease = lease is Map ? Map<String, dynamic>.from(lease) : null;
    notifyListeners();
  }

  Future<void> acceptInvitation(String invite) async {
    try {
      await dio.post('/v1/invitations/accept', data: {'token': invite.trim()});
    } on DioException catch (e) {
      throw OperationFailure(errorCode(e));
    }
    final stores = await availableStores();
    if (stores.isNotEmpty) await switchStore(stores.last);
  }

  Future<void> enableOffline() async {
    if (queue.isNotEmpty) throw const OperationFailure('pending_operations');
    await submit('/offline/enable', {'device_id': deviceId, 'hours': 8});
    await fetch('/products', paginated: true);
    await fetch('/customers', paginated: true);
  }

  Future<void> disableOffline() async {
    if (queue.isNotEmpty) throw const OperationFailure('pending_operations');
    await submit('/offline/disable', {
      'reason': 'Owner ended offline mode after queue confirmation',
    });
  }

  Future<void> setNotifications(bool enabled) async {
    if (enabled && !await StockNotifications.request()) {
      throw const OperationFailure('notificationDenied');
    }
    notificationsEnabled = enabled;
    await secure.write(key: 'stock_notifications', value: '$enabled');
    if (!enabled) {
      await StockNotifications.cancel();
      try {
        if (hasStore) {
          await dio.post(
            '$base/notifications/unregister',
            data: {'device_id': deviceId},
          );
        }
      } on DioException {
        /* Native delivery is disabled even while server is unavailable. */
      }
    }
    notifyListeners();
    if (enabled) await notifyLowStock();
  }

  Future<void> notifyLowStock() async {
    if (!notificationsEnabled || !authenticated || !hasStore) return;
    try {
      try {
        final pushToken = await StockNotifications.pushToken();
        if (pushToken != null) {
          await dio.post(
            '$base/notifications/register',
            data: {
              'device_id': deviceId,
              'token': pushToken,
              'language': language,
            },
          );
        }
      } catch (_) {
        /* Local reminders remain available without a cloud connection. */
      }
      final products = await fetch('/products', paginated: true) as List;
      final count = products
          .where((p) => p['stock'] <= p['minimum_stock'])
          .length;
      if (count == 0) {
        await StockNotifications.clear();
        return;
      }
      final previous = await db.cached('$namespace:stock_notice');
      if (previous is Map &&
          previous['count'] == count &&
          DateTime.now().difference(DateTime.parse(previous['time'])).inHours <
              4) {
        return;
      }
      await StockNotifications.show(
        language == 'ru' ? 'Проверьте остатки' : 'Qoldiqlarni tekshiring',
        language == 'ru'
            ? 'Товаров с низким остатком: $count'
            : 'Kam qolgan mahsulotlar: $count',
      );
      await db.cache('$namespace:stock_notice', {
        'count': count,
        'time': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {
      /* Notifications must not interrupt a sale or discard its queue. */
    }
  }

  Future<void> deleteAccount(String password) async {
    if (queue.isNotEmpty) throw const OperationFailure('pending_operations');
    try {
      await dio.post(
        '/v1/auth/delete',
        data: {'password': password, 'confirm': 'DELETE'},
      );
    } on DioException catch (e) {
      throw OperationFailure(errorCode(e));
    }
    final oldActor = actor!;
    await db.transaction(() async {
      await db.customStatement('DELETE FROM cache WHERE substr(key,1,?)=?', [
        oldActor.length + 1,
        '$oldActor:',
      ]);
      await db.customStatement(
        'DELETE FROM catalog WHERE substr(namespace,1,?)=?',
        [oldActor.length + 1, '$oldActor:'],
      );
    });
    await secure.delete(key: 'session');
    token = null;
    actor = null;
    storeId = null;
    storeName = '';
    queue = [];
    offlineLease = null;
    dio.options.headers.remove('Authorization');
    notifyListeners();
  }

  Future<void> reconcileOffline(String id, String reason) async {
    if (!isOwner) throw const OperationFailure('permission_denied');
    final command = queue.firstWhere((q) => q['id'] == id);
    if (command['state'] != 'conflict' || (command['lease'] ?? '').isEmpty) {
      throw const OperationFailure('invalid_request');
    }
    await send(command, resolution: reason);
  }

  Future<void> dismiss(String id) async {
    await db.dismissConflict(id);
    await readQueue();
    notifyListeners();
  }
}
