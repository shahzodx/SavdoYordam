import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/strings.dart';
import '../../design_system/data_view.dart';
import '../../design_system/theme.dart';
import '../../design_system/forms.dart';
import '../sales/sales_screen.dart';

class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(repositoryProvider);
    final s = context.text;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text(s['sync'])),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            SectionHeading(s['sync']),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        repo.queue.isEmpty
                            ? Icons.cloud_done_outlined
                            : Icons.cloud_upload_outlined,
                        color: brand,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          s[repo.queue.isEmpty ? 'synced' : 'pending'],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    s[repo.queue.isEmpty ? 'syncReadyHint' : 'queueHint'],
                    style: const TextStyle(color: muted),
                  ),
                  const SizedBox(height: 16),
                  AppButton(
                    label: s['syncNow'],
                    busy: repo.syncing,
                    icon: Icons.sync,
                    onPressed: () async {
                      await repo.sync();
                      refreshData(ref);
                      if (context.mounted) {
                        message(
                          context,
                          repo.queue.isEmpty ? 'synced' : 'pending_operations',
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
            for (final q in repo.queue)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StatusBadge(
                        label:
                            s[q['state'] == 'conflict'
                                ? 'conflict'
                                : 'pending'],
                        warning: true,
                      ),
                      const SizedBox(height: 10),
                      Text(_operationTitle(context, q['path'] as String)),
                      if (q['error'] != null) ...[
                        const SizedBox(height: 8),
                        Text(s[q['error']]),
                      ],
                      if (q['state'] == 'conflict' &&
                          (q['lease'] ?? '').isNotEmpty &&
                          repo.isOwner)
                        OutlinedButton.icon(
                          icon: const Icon(Icons.fact_check_outlined),
                          label: Text(s['resolveOffline']),
                          onPressed: () async {
                            final value = await appForm(
                              context,
                              'resolveOffline',
                              [const FieldSpec('reason', 'reason')],
                              note: s['resolveOfflineHint'],
                            );
                            if (value == null || !context.mounted) return;
                            await perform(
                              context,
                              ref,
                              () => repo.reconcileOffline(
                                q['id'],
                                value['reason']!,
                              ),
                            );
                          },
                        ),
                      if (q['state'] == 'conflict')
                        TextButton(
                          onPressed: () => perform(
                            context,
                            ref,
                            () => repo.dismiss(q['id']),
                          ),
                          child: Text(s['dismiss']),
                        ),
                    ],
                  ),
                ),
              ),
            DataView(
              path: '/offline',
              builder: (data) {
                final status = data as Map;
                if (status['active'] != true ||
                    status['device_id'] == repo.deviceId) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        NoticeCard(s['offlineOtherDevice'], warning: true),
                        if (repo.isOwner)
                          TextButton(
                            onPressed: () async {
                              final value = await appForm(
                                context,
                                'revokeOffline',
                                [const FieldSpec('reason', 'reason')],
                                note: s['revokeOfflineHint'],
                              );
                              if (value == null || !context.mounted) return;
                              await perform(context, ref, () async {
                                await repo.submit('/offline/disable', value);
                              });
                            },
                            child: Text(s['revokeOffline']),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
            if (repo.isOwner) ...[
              SectionHeading(s['offlineMode']),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (repo.offlineEnabled) ...[
                      StatusBadge(label: s['offlineActive']),
                      const SizedBox(height: 12),
                      Text(
                        '${s['expiresAt']}: ${displayDate(repo.offlineLease!['expires_at'])}',
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text(
                      s['offlinePolicy'],
                      style: const TextStyle(color: muted),
                    ),
                    const SizedBox(height: 16),
                    AppButton(
                      label:
                          s[repo.offlineEnabled
                              ? 'offlineDisable'
                              : 'offlineEnable'],
                      icon: Icons.offline_bolt_outlined,
                      onPressed: repo.queue.isNotEmpty
                          ? null
                          : () => perform(
                              context,
                              ref,
                              repo.offlineEnabled
                                  ? repo.disableOffline
                                  : repo.enableOffline,
                            ),
                    ),
                    if (repo.queue.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          s['pending_operations'],
                          style: const TextStyle(color: amber),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _operationTitle(BuildContext context, String path) {
    final parts = path.split('/');
    final last = parts.last;
    if (parts.length > 2 && parts[parts.length - 2] == 'products') {
      return context.text['editProduct'];
    }
    return context.text[switch (last) {
      'payments' => 'repay',
      'return' => 'fullReturn',
      'inventory' => 'adjustStock',
      _ => last,
    }];
  }
}
