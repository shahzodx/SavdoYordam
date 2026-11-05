import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/strings.dart';
import '../../design_system/data_view.dart';
import '../../design_system/theme.dart';
import '../../design_system/forms.dart';
import '../../design_system/pickers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(repositoryProvider);
    final s = context.text;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text(s['settings'])),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            AppCard(
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: softBrand,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.storefront_outlined,
                      color: brand,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          repo.storeName,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          s['version'],
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppCard(
              padding: 4,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.storefront_outlined),
                    title: Text(s['switchStore']),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => perform(context, ref, () async {
                      final stores = await repo.availableStores();
                      if (!context.mounted) return;
                      final selected = await chooseRecord(
                        context,
                        'switchStore',
                        stores,
                      );
                      if (selected != null) await repo.switchStore(selected);
                    }),
                  ),
                  ListTile(
                    leading: const Icon(Icons.add_business_outlined),
                    title: Text(s['createStore']),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final value = await appForm(context, 'createStore', [
                        const FieldSpec('name', 'storeName'),
                        const FieldSpec(
                          'retail_type',
                          'retailType',
                          initial: 'general',
                          options: [
                            'general',
                            'grocery',
                            'clothing',
                            'household',
                            'other',
                          ],
                        ),
                      ]);
                      if (value == null || !context.mounted) return;
                      await perform(
                        context,
                        ref,
                        () => repo.createStore(
                          value['name']!,
                          retailType: value['retail_type']!,
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.key_outlined),
                    title: Text(s['joinStore']),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final value = await appForm(context, 'joinStore', [
                        const FieldSpec('token', 'invitationCode'),
                      ]);
                      if (value == null || !context.mounted) return;
                      await perform(
                        context,
                        ref,
                        () => repo.acceptInvitation(value['token']!),
                      );
                    },
                  ),
                  if (repo.isOwner) ...[
                    ListTile(
                      leading: const Icon(Icons.people_outline),
                      title: Text(s['team']),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/team'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.local_shipping_outlined),
                      title: Text(s['purchases']),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/purchases'),
                    ),
                  ],
                  ListTile(
                    leading: const Icon(Icons.payments_outlined),
                    title: Text(s['currency']),
                    trailing: const Text('UZS'),
                  ),
                ],
              ),
            ),
            SectionHeading(s['account']),
            AppCard(
              padding: 4,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: Text(s['security']),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/security'),
                  ),
                  if (repo.isOwner)
                    ListTile(
                      leading: const Icon(Icons.history_rounded),
                      title: Text(s['audit']),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/audit'),
                    ),
                  if (repo.isOwner)
                    ListTile(
                      leading: const Icon(Icons.download_outlined),
                      title: Text(s['export']),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/export'),
                    ),
                  if (repo.isOwner)
                    ListTile(
                      leading: const Icon(Icons.edit_outlined),
                      title: Text(s['storeInformation']),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => perform(context, ref, () async {
                        final store = await repo.fetch('/settings') as Map;
                        if (!context.mounted) return;
                        final value = await appForm(
                          context,
                          'storeInformation',
                          [
                            FieldSpec(
                              'name',
                              'storeName',
                              initial: store['name'],
                            ),
                            FieldSpec(
                              'retail_type',
                              'retailType',
                              initial: store['retail_type'],
                              options: const [
                                'general',
                                'grocery',
                                'clothing',
                                'household',
                                'other',
                              ],
                            ),
                          ],
                        );
                        if (value != null) {
                          await repo.submit('/settings', value);
                        }
                      }),
                    ),
                ],
              ),
            ),
            SectionHeading(s['language']),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'uz', label: Text('O‘zbekcha')),
                ButtonSegment(value: 'ru', label: Text('Русский')),
              ],
              selected: {repo.language},
              onSelectionChanged: (v) => repo.setLanguage(v.first),
            ),
            SectionHeading(s['notifications']),
            AppCard(
              padding: 4,
              child: SwitchListTile(
                value: repo.notificationsEnabled,
                title: Text(s['stockNotifications']),
                subtitle: Text(s['notificationHint']),
                onChanged: (v) =>
                    perform(context, ref, () => repo.setNotifications(v)),
              ),
            ),
            SectionHeading(s['data']),
            AppCard(
              padding: 4,
              child: ListTile(
                leading: Badge.count(
                  count: repo.queue.length,
                  isLabelVisible: repo.queue.isNotEmpty,
                  child: const Icon(Icons.cloud_sync_outlined),
                ),
                title: Text(s['sync']),
                subtitle: Text(s[repo.queue.isEmpty ? 'synced' : 'pending']),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/sync'),
              ),
            ),
            SectionHeading(s['support']),
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: Text(s['help']),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => info(context, 'help', 'helpBody'),
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: Text(s['privacy']),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => info(context, 'privacy', 'privacyBody'),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => context.push('/login'),
              child: Text(s['reauth']),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => perform(context, ref, repo.logout),
              icon: const Icon(Icons.logout),
              label: Text(s['logout']),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void info(BuildContext context, String title, String body) =>
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.text[title]),
          content: SingleChildScrollView(child: Text(context.text[body])),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.text['close']),
            ),
          ],
        ),
      );
}
