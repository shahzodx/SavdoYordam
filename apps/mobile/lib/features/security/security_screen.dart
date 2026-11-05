import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/strings.dart';
import '../../design_system/data_view.dart';
import '../../design_system/forms.dart';
import '../../design_system/theme.dart';
import '../sales/sales_screen.dart';

class SecurityScreen extends ConsumerStatefulWidget {
  const SecurityScreen({super.key});
  @override
  ConsumerState<SecurityScreen> createState() => _SecurityState();
}

class _SecurityState extends ConsumerState<SecurityScreen> {
  List sessions = [];
  bool loading = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final result =
          (await ref.read(repositoryProvider).dio.get('/v1/auth/sessions')).data
              as List;
      if (mounted) setState(() => sessions = result);
    } catch (_) {
      if (mounted) message(context, 'connection_error');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> changePassword() async {
    final value = await appForm(context, 'changePassword', [
      const FieldSpec('current_password', 'currentPassword', secret: true),
      FieldSpec(
        'new_password',
        'newPassword',
        secret: true,
        validate: (s) => s.length >= 12,
      ),
    ], note: context.text['passwordChangeHint']);
    if (value == null || !mounted) return;
    try {
      await ref
          .read(repositoryProvider)
          .dio
          .post('/v1/auth/password', data: value);
      if (mounted) message(context, 'saved');
      await load();
    } on DioException catch (e) {
      if (mounted) message(context, ref.read(repositoryProvider).errorCode(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.text;
    return Scaffold(
      appBar: AppBar(title: Text(s['security'])),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          AppButton(
            label: s['changePassword'],
            icon: Icons.lock_outline,
            onPressed: changePassword,
          ),
          SectionHeading(s['sessions']),
          if (loading) const Center(child: CircularProgressIndicator()),
          for (final session in sessions)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AppCard(
                padding: 4,
                child: ListTile(
                  leading: const Icon(Icons.phone_android_outlined),
                  title: Text(
                    s[session['current'] == true
                        ? 'currentSession'
                        : 'otherSession'],
                  ),
                  subtitle: Text(displayDate(session['created_at'])),
                  trailing: session['current'] == true
                      ? null
                      : IconButton(
                          tooltip: s['revokeAccess'],
                          icon: const Icon(Icons.logout),
                          onPressed: () async {
                            try {
                              await ref
                                  .read(repositoryProvider)
                                  .dio
                                  .post(
                                    '/v1/auth/sessions/revoke',
                                    data: {'id': session['id']},
                                  );
                              await load();
                            } catch (_) {
                              if (context.mounted) {
                                message(context, 'connection_error');
                              }
                            }
                          },
                        ),
                ),
              ),
            ),
          const SizedBox(height: 24),
          TextButton.icon(
            icon: const Icon(Icons.person_remove_outlined),
            label: Text(
              s['deleteAccount'],
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onPressed: () async {
              final value = await appForm(
                context,
                'deleteAccount',
                [
                  const FieldSpec('password', 'currentPassword', secret: true),
                  FieldSpec(
                    'confirm',
                    'deleteConfirm',
                    validate: (v) => v == 'DELETE',
                  ),
                ],
                note: s['deleteAccountHint'],
                confirm: s['deleteAccount'],
              );
              if (value == null || !context.mounted) return;
              await perform(
                context,
                ref,
                () => ref
                    .read(repositoryProvider)
                    .deleteAccount(value['password']!),
              );
            },
          ),
        ],
      ),
    );
  }
}
