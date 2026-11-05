import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/amounts.dart';
import '../../core/strings.dart';
import '../../design_system/data_view.dart';
import '../../design_system/forms.dart';
import '../../design_system/theme.dart';

String displayDate(String value) =>
    DateFormat('dd.MM · HH:mm')
        .format(DateTime.parse(value).toUtc().add(const Duration(hours: 5)));

class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({super.key});
  @override
  ConsumerState<SalesScreen> createState() => _SalesState();
}

class _SalesState extends ConsumerState<SalesScreen> {
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
              PageHeading(s['sales'], subtitle: s['salesHint']),
              AppSearchField(
                hint: s['searchSales'],
                onChanged: (v) =>
                    setState(() => query = v.trim().toLowerCase()),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final f in [
                      'all',
                      'withDebt',
                      'paidInFull',
                      'returned',
                    ])
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
            path: '/sales',
            builder: (data) {
              final rows = (data as List).where((sale) {
                final returned = sale['returned'] == true;
                final debt =
                    (sale['total'] as int) -
                    (sale['returned_total'] as int? ?? 0) -
                    (sale['paid'] as int);
                return '${sale['customer_name'] ?? ''} ${sale['id']} ${displayDate(sale['created_at'])}'
                        .toLowerCase()
                        .contains(query) &&
                    switch (filter) {
                      'withDebt' => !returned && debt > 0,
                      'paidInFull' => !returned && debt == 0,
                      'returned' => returned,
                      _ => true,
                    };
              }).toList();
              return RefreshIndicator(
                onRefresh: () async => refreshData(ref),
                child: rows.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          EmptyState(
                            icon: query.isEmpty && filter == 'all'
                                ? Icons.receipt_long_outlined
                                : Icons.search_off_rounded,
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
                                    label: s['newSale'],
                                    onPressed: () => context.push('/pos'),
                                  )
                                : null,
                          ),
                        ],
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
                        itemCount: rows.length,
                        itemBuilder: (context, i) =>
                            SaleTile(sale: Map<String, dynamic>.from(rows[i])),
                      ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class SaleTile extends ConsumerWidget {
  const SaleTile({super.key, required this.sale});
  final Map<String, dynamic> sale;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.text;
    final returned = sale['returned'] == true;
    final debt = returned
        ? 0
        : (sale['total'] as int) -
              (sale['returned_total'] as int? ?? 0) -
              (sale['paid'] as int);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: border),
        ),
        child: InkWell(
          onTap: () => saleSheet(context, ref, sale),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        money(sale['total'], s.locale.languageCode),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: muted),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  sale['customer_name'] ?? s['anonymous'],
                  style: const TextStyle(color: muted),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      displayDate(sale['created_at']),
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                    StatusBadge(
                      label: returned
                          ? s['returned']
                          : debt > 0
                          ? '${s['debtRemaining']}: ${money(debt, s.locale.languageCode)}'
                          : s['paidInFull'],
                      warning: returned || debt > 0,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> saleSheet(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> sale,
) async {
  final debt = sale['returned'] == true
      ? 0
      : (sale['total'] as int) -
            (sale['returned_total'] as int? ?? 0) -
            (sale['paid'] as int);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheet) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .75,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            context.text['sale'],
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          Text(
            money(sale['total'], context.text.locale.languageCode),
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 8),
          Text(displayDate(sale['created_at'])),
          const SizedBox(height: 16),
          Text(
            '${context.text['received']}: ${money(sale['paid'], context.text.locale.languageCode)}',
          ),
          Text(
            '${context.text['debtRemaining']}: ${money(debt, context.text.locale.languageCode)}',
          ),
          const SizedBox(height: 20),
          DataView(
            path: '/sales/${sale['id']}',
            builder: (data) => Column(
              children: (data as List)
                  .map(
                    (p) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(p['name']),
                      subtitle: Text(
                        '${quantity(p['quantity'])} × ${money(p['price'], context.text.locale.languageCode)}',
                      ),
                      trailing: Text(
                        money(p['total'], context.text.locale.languageCode),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 24),
          if (debt > 0)
            AppButton(
              label: context.text['repay'],
              icon: Icons.payments_outlined,
              onPressed: () async {
                final p = await appForm(
                  context,
                  'repay',
                  [
                    FieldSpec(
                      'amount',
                      'amount',
                      initial:
                          '${debt ~/ 100}.${(debt % 100).toString().padLeft(2, '0')}',
                      numeric: true,
                      validate: (s) {
                        final n = parseScaled(s, 2);
                        return n != null && n > 0 && n <= debt;
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
                      '${sale['customer_name'] ?? ''}\n${context.text['debtRemaining']}: ${money(debt, context.text.locale.languageCode)}',
                );
                if (p == null || !context.mounted) return;
                final amount = parseScaled(p['amount']!, 2)!;
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialog) => AlertDialog(
                    title: Text(context.text['repay']),
                    content: Text(
                      '${sale['customer_name'] ?? ''}\n${money(amount, context.text.locale.languageCode)}\n${context.text['debtRemaining']}: ${money(debt - amount, context.text.locale.languageCode)}',
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
                    '/sales/${sale['id']}/payments',
                    {'amount': amount, 'method': p['method']},
                  );
                });
                if (sheet.mounted) Navigator.pop(sheet);
              },
            ),
          if (sale['returned'] != true &&
              ref.read(repositoryProvider).isOwner) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.undo),
              label: Text(context.text['processReturn']),
              onPressed: () async {
                final rows =
                    await ref
                            .read(repositoryProvider)
                            .fetch('/sales/${sale['id']}')
                        as List;
                if (!context.mounted) return;
                final available = rows
                    .where((p) => p['quantity'] > (p['returned_quantity'] ?? 0))
                    .toList();
                final p = await appForm(
                  context,
                  'processReturn',
                  [
                    const FieldSpec('reason', 'reason'),
                    for (final item in available)
                      FieldSpec(
                        item['product_id'],
                        'quantity',
                        literalLabel: item['name'],
                        initial: quantity(
                          item['quantity'] - (item['returned_quantity'] ?? 0),
                        ),
                        numeric: true,
                        validate: (s) {
                          final q = parseScaled(s, 3);
                          return q != null &&
                              q >= 0 &&
                              q <=
                                  item['quantity'] -
                                      (item['returned_quantity'] ?? 0) &&
                              (item['unit'] != 'piece' || q % 1000 == 0);
                        },
                      ),
                  ],
                  note: context.text['returnHint'],
                  confirm: context.text['confirm'],
                );
                if (p == null || !context.mounted) return;
                if (!available.any(
                  (item) => (parseScaled(p[item['product_id']]!, 3) ?? 0) > 0,
                )) {
                  message(context, 'invalid_quantity');
                  return;
                }
                await perform(context, ref, () async {
                  await ref.read(repositoryProvider).submit(
                    '/sales/${sale['id']}/return',
                    {
                      'reason': p['reason'],
                      'items': [
                        for (final item in available)
                          if ((parseScaled(p[item['product_id']]!, 3) ?? 0) > 0)
                            {
                              'product_id': item['product_id'],
                              'quantity': parseScaled(
                                p[item['product_id']]!,
                                3,
                              ),
                            },
                      ],
                    },
                  );
                });
                if (sheet.mounted) Navigator.pop(sheet);
              },
            ),
          ],
        ],
      ),
    ),
  );
}
