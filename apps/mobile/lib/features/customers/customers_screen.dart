import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/amounts.dart';
import '../../core/strings.dart';
import '../../design_system/data_view.dart';
import '../../design_system/forms.dart';
import '../../design_system/theme.dart';
import '../sales/sales_screen.dart';

Future<void> addCustomer(BuildContext context, WidgetRef ref) async {
  final p = await appForm(context, 'addCustomer', [
    const FieldSpec('name', 'customerName'),
    const FieldSpec('phone', 'phone', optional: true, phone: true),
  ]);
  if (p == null || !context.mounted) return;
  await perform(context, ref, () async {
    await ref.read(repositoryProvider).submit('/customers', p);
  });
}

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});
  @override
  ConsumerState<CustomersScreen> createState() => _CustomersState();
}

class _CustomersState extends ConsumerState<CustomersScreen> {
  String query = '', filter = 'all';
  @override
  Widget build(BuildContext context) {
    final s = context.text;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeading(s['customers'], subtitle: s['customersHint']),
              AppSearchField(
                hint: s['searchCustomers'],
                onChanged: (v) =>
                    setState(() => query = v.trim().toLowerCase()),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final f in ['all', 'withDebt', 'withoutDebt'])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(s[f]),
                          selected: filter == f,
                          onSelected: (_) => setState(() => filter = f),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
        Expanded(
          child: DataView(
            path: '/customers',
            builder: (data) {
              final rows = (data as List)
                  .where(
                    (c) =>
                        '${c['name']} ${c['phone'] ?? ''}'
                            .toLowerCase()
                            .contains(query) &&
                        (filter == 'all' ||
                            (filter == 'withDebt'
                                ? (c['debt'] as int) > 0
                                : c['debt'] == 0)),
                  )
                  .toList();
              if (filter == 'withDebt') {
                rows.sort(
                  (a, b) => (b['debt'] as int).compareTo(a['debt'] as int),
                );
              }
              return RefreshIndicator(
                onRefresh: () async => refreshData(ref),
                child: rows.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          EmptyState(
                            icon: Icons.people_outline,
                            title:
                                s[query.isEmpty && filter == 'all'
                                    ? 'empty'
                                    : 'nothingFound'],
                            hint:
                                s[query.isEmpty && filter == 'all'
                                    ? 'emptyHint'
                                    : 'tryAnotherSearch'],
                            action: query.isEmpty && filter == 'all'
                                ? AppButton(
                                    label: s['addCustomer'],
                                    onPressed: () => addCustomer(context, ref),
                                  )
                                : null,
                          ),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final c = rows[i];
                          return AppCard(
                            padding: 4,
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              onTap: () => customerSheet(context, c),
                              leading: CircleAvatar(
                                backgroundColor: softBrand,
                                child: Text(
                                  c['name']
                                      .toString()
                                      .characters
                                      .first
                                      .toUpperCase(),
                                  style: const TextStyle(
                                    color: brand,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              title: Text(
                                c['name'],
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      c['debt'] > 0
                                          ? money(
                                              c['debt'],
                                              s.locale.languageCode,
                                            )
                                          : s['noDebt'],
                                      style: TextStyle(
                                        color: c['debt'] > 0 ? amber : muted,
                                        fontWeight: c['debt'] > 0
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                      ),
                                    ),
                                    if ((c['phone'] ?? '').isNotEmpty)
                                      Text(
                                        c['phone'],
                                        style: const TextStyle(
                                          color: muted,
                                          fontSize: 12,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              trailing: const Icon(
                                Icons.chevron_right,
                                color: muted,
                              ),
                            ),
                          );
                        },
                      ),
              );
            },
          ),
        ),
      ],
    );
  }

  void customerSheet(
    BuildContext context,
    dynamic c,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .8,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.all(24),
        children: [
          Text(c['name'], style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          AppCard(
            color: c['debt'] > 0 ? const Color(0xFFFFF6E6) : softBrand,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.text['debtRemaining'],
                  style: const TextStyle(color: muted),
                ),
                const SizedBox(height: 8),
                Text(
                  money(c['debt'], context.text.locale.languageCode),
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(color: c['debt'] > 0 ? amber : brand),
                ),
              ],
            ),
          ),
          if ((c['phone'] ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(c['phone']),
            ),
          if (c['debt'] > 0)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: AppButton(
                label: context.text['repay'],
                icon: Icons.payments_outlined,
                onPressed: () async {
                  final value = await appForm(
                    context,
                    'repay',
                    [
                      FieldSpec(
                        'amount',
                        'amount',
                        initial:
                            '${c['debt'] ~/ 100}.${(c['debt'] % 100).toString().padLeft(2, '0')}',
                        numeric: true,
                        validate: (s) {
                          final n = parseScaled(s, 2);
                          return n != null && n > 0 && n <= c['debt'];
                        },
                      ),
                      const FieldSpec(
                        'method',
                        'method',
                        initial: 'cash',
                        options: ['cash', 'card'],
                      ),
                    ],
                    note:
                        '${c['name']} · ${context.text['debtRemaining']}: ${money(c['debt'], context.text.locale.languageCode)}',
                  );
                  if (value == null || !context.mounted) return;
                  final amount = parseScaled(value['amount']!, 2)!;
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialog) => AlertDialog(
                      title: Text(context.text['repay']),
                      content: Text(
                        '${c['name']}\n${money(amount, context.text.locale.languageCode)}\n${context.text['debtRemaining']}: ${money(c['debt'] - amount, context.text.locale.languageCode)}',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialog, false),
                          child: Text(context.text['cancel']),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialog, true),
                          child: Text(context.text['confirm']),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true || !context.mounted) return;
                  await perform(context, ref, () async {
                    await ref.read(repositoryProvider).submit(
                      '/customers/${c['id']}/payments',
                      {'amount': amount, 'method': value['method']},
                    );
                  });
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ),
          SectionHeading(context.text['purchaseHistory']),
          DataView(
            path: '/sales?customer_id=${c['id']}',
            builder: (data) => Column(
              children: (data as List)
                  .map((s) => SaleTile(sale: Map<String, dynamic>.from(s)))
                  .toList(),
            ),
          ),
          SectionHeading(context.text['ledger']),
          DataView(
            path: '/customers/${c['id']}/ledger',
            builder: (data) => Column(
              children: (data as List)
                  .map(
                    (r) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        context.text[r['kind'] == 'sale'
                            ? 'debtSale'
                            : r['kind']],
                      ),
                      subtitle: Text(displayDate(r['created_at'])),
                      trailing: Text(
                        money(r['amount'], context.text.locale.languageCode),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    ),
  );
}
