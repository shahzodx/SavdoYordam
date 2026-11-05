import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/repository.dart';

final repositoryProvider = Provider<Repository>(
  (ref) =>
      throw StateError('Repository must be provided by application bootstrap'),
);
final dataProvider = FutureProvider.autoDispose.family<Object, String>((
  ref,
  path,
) {
  final repo = ref.watch(repositoryProvider);
  return repo.fetch(
    path,
    paginated:
        [
          '/products',
          '/customers',
          '/sales',
          '/expenses',
          '/purchases',
          '/audit',
        ].contains(path.split('?').first) ||
        path.startsWith('/inventory/') ||
        path.endsWith('/ledger'),
  );
});
void refreshData(WidgetRef ref) => ref.invalidate(dataProvider);
