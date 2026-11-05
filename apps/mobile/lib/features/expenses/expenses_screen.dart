import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/amounts.dart';
import '../../core/strings.dart';
import '../../design_system/data_view.dart';
import '../../design_system/forms.dart';
import '../../design_system/theme.dart';

Future<void> addExpense(BuildContext context, WidgetRef ref) async {
  final p = await appForm(context, 'addExpense', [
    FieldSpec(
      'amount',
      'amount',
      numeric: true,
      validate: (s) => (parseScaled(s, 2) ?? 0) > 0,
    ),
    const FieldSpec(
      'category',
      'category',
      initial: 'rent',
      options: ['rent', 'salary', 'delivery', 'utilities', 'other'],
    ),
    const FieldSpec(
      'method',
      'method',
      initial: 'cash',
      options: ['cash', 'card'],
    ),
    FieldSpec(
      'occurred_on',
      'date',
      date: true,
      initial: DateFormat('yyyy-MM-dd')
          .format(DateTime.now().toUtc().add(const Duration(hours: 5))),
      validate: (s) =>
          RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s) &&
          DateTime.tryParse(s) != null,
    ),
    const FieldSpec('description', 'description', optional: true),
  ]);
  if (p == null || !context.mounted) return;
  await perform(context, ref, () async {
    await ref.read(repositoryProvider).submit('/expenses', {
      ...p,
      'amount': parseScaled(p['amount']!, 2),
    });
  });
}

class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: Text(context.text['expenses'])),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => addExpense(context, ref),
      label: Text(context.text['addExpense']),
      icon: const Icon(Icons.add),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        DataView(
          path: '/expenses',
          builder: (data) => (data as List).isEmpty
              ? const EmptyState()
              : Column(
                  children: data
                      .map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: AppCard(
                            padding: 4,
                            child: ListTile(
                              trailing: e['voided'] == true
                                  ? StatusBadge(
                                      label: context.text['voided'],
                                      warning: true,
                                    )
                                  : null,
                              onTap:
                                  e['voided'] == true ||
                                      !ref.read(repositoryProvider).isOwner
                                  ? null
                                  : () async {
                                      final value = await appForm(
                                        context,
                                        'voidExpense',
                                        [const FieldSpec('reason', 'reason')],
                                        note: context.text['voidExpenseHint'],
                                      );
                                      if (value == null || !context.mounted) {
                                        return;
                                      }
                                      await perform(context, ref, () async {
                                        await ref
                                            .read(repositoryProvider)
                                            .submit(
                                              '/expenses/${e['id']}/void',
                                              value,
                                            );
                                      });
                                    },
                              title: Text(
                                money(
                                  e['amount'],
                                  context.text.locale.languageCode,
                                ),
                              ),
                              subtitle: Text(
                                '${context.text[e['category']]} · ${e['occurred_on'].toString().substring(0, 10)}\n${e['description']}',
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
        const SizedBox(height: 80),
      ],
    ),
  );
}
