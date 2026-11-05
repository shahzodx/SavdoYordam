import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';

final catalogSourceProvider = FutureProvider<void>((ref) async {
  final products = await ref.watch(dataProvider('/products').future) as List;
  final repo = ref.read(repositoryProvider);
  await repo.db.transaction(() async {
    final current = await repo.db.cached('${repo.namespace}:/products');
    await repo.db.replaceCatalog(
      repo.namespace,
      current is List ? current : products,
    );
  });
});

typedef CatalogQuery = ({String query, String category, String ids, int limit});
final catalogSearchProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, CatalogQuery>((ref, request) async {
      await ref.watch(catalogSourceProvider.future);
      final repo = ref.read(repositoryProvider);
      return repo.db.searchCatalog(
        repo.namespace,
        request.query,
        category: request.category,
        limit: request.limit,
        ids: request.ids.isEmpty ? null : request.ids.split(','),
      );
    });
