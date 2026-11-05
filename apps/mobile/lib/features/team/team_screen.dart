import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/strings.dart';
import '../../design_system/data_view.dart';
import '../../design_system/forms.dart';
import '../../design_system/theme.dart';

class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});
  Future<void> invite(BuildContext context, WidgetRef ref) async {
    final values = await appForm(context, 'inviteEmployee', [
      const FieldSpec('email', 'email'),
    ], note: context.text['invitationHint']);
    if (values == null || !context.mounted) return;
    await perform(context, ref, () async {
      final result = await ref
          .read(repositoryProvider)
          .submit('/invitations', values);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(context.text['invitationCode']),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.text['invitationHint']),
                const SizedBox(height: 16),
                SelectableText(result['token']),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: result['token']));
                if (dialog.mounted) Navigator.pop(dialog);
              },
              child: Text(context.text['copy']),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: Text(context.text['close']),
            ),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.text;
    return Scaffold(
      appBar: AppBar(title: Text(s['team'])),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          NoticeCard(s['teamHint'], icon: Icons.people_outline),
          SectionHeading(s['employees']),
          DataView(
            path: '/members',
            builder: (data) => Column(
              children: [
                for (final m in data as List)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                      padding: 4,
                      child: ListTile(
                        title: Text(m['email']),
                        subtitle: Text(s[m['role']]),
                        leading: const Icon(Icons.person_outline),
                        trailing: m['role'] == 'owner'
                            ? null
                            : IconButton(
                                tooltip: s['revokeAccess'],
                                icon: const Icon(Icons.person_remove_outlined),
                                onPressed: () async {
                                  final value = await appForm(
                                    context,
                                    'revokeAccess',
                                    [const FieldSpec('reason', 'reason')],
                                    note: m['email'],
                                  );
                                  if (value == null || !context.mounted) return;
                                  await perform(context, ref, () async {
                                    await ref
                                        .read(repositoryProvider)
                                        .submit(
                                          '/members/${m['id']}/remove',
                                          value,
                                        );
                                  });
                                },
                              ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SectionHeading(s['invitations']),
          DataView(
            path: '/invitations',
            builder: (data) => Column(
              children: [
                for (final i in data as List)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                      padding: 4,
                      child: ListTile(
                        title: Text(i['email']),
                        subtitle: Text(
                          s[i['accepted_by'] != null
                              ? 'invitationAccepted'
                              : i['revoked'] == true
                              ? 'invitationRevoked'
                              : 'invitationPending'],
                        ),
                        trailing:
                            i['accepted_by'] != null || i['revoked'] == true
                            ? null
                            : IconButton(
                                tooltip: s['revokeAccess'],
                                icon: const Icon(Icons.close),
                                onPressed: () =>
                                    perform(context, ref, () async {
                                      await ref.read(repositoryProvider).submit(
                                        '/invitations/${i['id']}/revoke',
                                        {'reason': 'Owner revoked invitation'},
                                      );
                                    }),
                              ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => invite(context, ref),
        icon: const Icon(Icons.person_add_outlined),
        label: Text(s['inviteEmployee']),
      ),
    );
  }
}
