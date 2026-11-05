import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/repository.dart';
import '../core/strings.dart';
import 'theme.dart';

class DataView extends ConsumerWidget {
  const DataView({super.key, required this.path, required this.builder});
  final String path;
  final Widget Function(Object) builder;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(dataProvider(path))
      .when(
        data: builder,
        loading: () => const LoadingSkeleton(),
        error: (error, stack) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 36, color: muted),
              const SizedBox(height: 16),
              Text(
                context.text[error is OperationFailure ? error.code : 'error'],
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              AppButton(
                label: context.text['retry'],
                onPressed: () => ref.invalidate(dataProvider(path)),
              ),
            ],
          ),
        ),
      );
}

void message(BuildContext context, String key) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(context.text[key]),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

Future<void> perform(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() action,
) async {
  try {
    await action();
    refreshData(ref);
    if (context.mounted) message(context, 'saved');
  } on OperationFailure catch (e) {
    if (context.mounted) message(context, e.code);
  } catch (_) {
    if (context.mounted) message(context, 'server_error');
  }
}
