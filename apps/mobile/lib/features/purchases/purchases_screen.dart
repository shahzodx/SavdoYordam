import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/amounts.dart';
import '../../core/strings.dart';
import '../../design_system/data_view.dart';
import '../../design_system/forms.dart';
import '../../design_system/pickers.dart';
import '../../design_system/theme.dart';
import '../sales/sales_screen.dart';

class PurchasesScreen extends ConsumerWidget {
  const PurchasesScreen({super.key});
  Future<void> add(BuildContext context, WidgetRef ref) async {
    try {
      final repo = ref.read(repositoryProvider);
      final products = await repo.fetch('/products', paginated: true) as List;
      if (!context.mounted) return;
      final product = await chooseRecord(context, 'chooseProduct', products);
      if (product == null || !context.mounted) return;
      final value = await appForm(context, 'receiveStock', [
        FieldSpec(
          'quantity',
          'quantity',
          numeric: true,
          validate: (s) {
            final q = parseScaled(s, 3);
            return q != null &&
                q > 0 &&
                (product['unit'] != 'piece' || q % 1000 == 0);
          },
        ),
        FieldSpec(
          'unit_cost',
          'purchasePrice',
          numeric: true,
          validate: (s) => (parseScaled(s, 2) ?? 0) > 0,
        ),
        const FieldSpec('supplier', 'supplier', optional: true),
        const FieldSpec('note', 'description', optional: true),
      ], note: '${product['name']} · ${context.text[product['unit']]}');
      if (value == null || !context.mounted) return;
      await perform(context, ref, () async {
        await repo.submit('/purchases', {
          'supplier': value['supplier'],
          'note': value['note'],
          'items': [
            {
              'product_id': product['id'],
              'quantity': parseScaled(value['quantity']!, 3),
              'unit_cost': parseScaled(value['unit_cost']!, 2),
            },
          ],
        });
      });
    } catch (_) {
      if (context.mounted) message(context, 'connection_error');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.text;
    return Scaffold(
      appBar: AppBar(title: Text(s['purchases'])),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          NoticeCard(s['purchaseHint'], icon: Icons.local_shipping_outlined),
          const SizedBox(height: 20),
          DataView(
            path: '/purchases',
            builder: (data) => (data as List).isEmpty
                ? EmptyState(
                    icon: Icons.local_shipping_outlined,
                    action: AppButton(
                      label: s['receiveStock'],
                      onPressed: () => add(context, ref),
                    ),
                  )
                : Column(
                    children: [
                      for (final p in data)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: AppCard(
                            padding: 4,
                            child: ListTile(
                              title: Text(
                                money(p['total'], s.locale.languageCode),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              subtitle: Text(
                                '${p['supplier'].toString().isEmpty ? s['purchase'] : p['supplier']}\n${displayDate(p['created_at'])}',
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => showModalBottomSheet<void>(
                                context: context,
                                isScrollControlled: true,
                                useSafeArea: true,
                                builder: (context) => AppSheet(
                                  title: s['purchase'],
                                  child: DataView(
                                    path: '/purchases/${p['id']}',
                                    builder: (items) => Column(
                                      children: [
                                        for (final i in items as List)
                                          ListTile(
                                            title: Text(i['name']),
                                            subtitle: Text(
                                              '${quantity(i['quantity'])} × ${money(i['unit_cost'], s.locale.languageCode)}',
                                            ),
                                            trailing: Text(
                                              money(
                                                i['total'],
                                                s.locale.languageCode,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
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
        onPressed: () => add(context, ref),
        icon: const Icon(Icons.add),
        label: Text(s['receiveStock']),
      ),
    );
  }
}
