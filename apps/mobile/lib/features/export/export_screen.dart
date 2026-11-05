import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/amounts.dart';
import '../../core/export_file.dart';
import '../../core/strings.dart';
import '../../design_system/data_view.dart';
import '../../design_system/theme.dart';

class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});
  @override
  ConsumerState<ExportScreen> createState() => _ExportState();
}

class _ExportState extends ConsumerState<ExportScreen> {
  bool busy = false;
  String decimal(int amount) =>
      '${amount ~/ 100}.${(amount.abs() % 100).toString().padLeft(2, '0')}';
  Future<void> export(String kind) async {
    setState(() => busy = true);
    try {
      final repo = ref.read(repositoryProvider);
      final snapshot = (await repo.dio.get('${repo.base}/export')).data as Map;
      final stamp = DateTime.now().toUtc().toIso8601String().substring(0, 10);
      bool saved;
      if (kind == 'all') {
        saved = await ExportFile.saveJson(snapshot, 'SavdoYordam-$stamp.json');
      } else {
        final rows = <List<Object?>>[];
        if (kind == 'products') {
          rows.add([
            'ID',
            'Name',
            'SKU',
            'Category',
            'Unit',
            'Price UZS',
            'Cost UZS',
            'Stock',
          ]);
          for (final p in snapshot['products'] as List) {
            rows.add([
              p['id'],
              p['name'],
              p['sku'],
              p['category'],
              p['unit'],
              decimal(p['price']),
              p['cost'] == null ? '' : decimal(p['cost']),
              quantity(p['stock']),
            ]);
          }
        } else if (kind == 'customers') {
          rows.add(['ID', 'Name', 'Phone', 'Debt UZS']);
          final debt = <String, int>{};
          for (final d in snapshot['debt_entries'] as List) {
            debt[d['customer_id']] =
                (debt[d['customer_id']] ?? 0) + (d['amount'] as int);
          }
          for (final c in snapshot['customers'] as List) {
            rows.add([
              c['id'],
              c['name'],
              c['phone'],
              decimal(debt[c['id']] ?? 0),
            ]);
          }
        } else {
          rows.add([
            'ID',
            'Date UTC',
            'Customer ID',
            'Total UZS',
            'Returned UZS',
            'Paid UZS',
            'Debt UZS',
          ]);
          final paid = <String, int>{}, returned = <String, int>{};
          for (final p in snapshot['payments'] as List) {
            paid[p['sale_id']] =
                (paid[p['sale_id']] ?? 0) + (p['amount'] as int);
          }
          for (final r in snapshot['returns'] as List) {
            returned[r['sale_id']] =
                (returned[r['sale_id']] ?? 0) + (r['total'] as int);
          }
          for (final s in snapshot['sales'] as List) {
            final id = s['id'] as String;
            rows.add([
              id,
              s['created_at'],
              s['customer_id'],
              decimal(s['total']),
              decimal(returned[id] ?? 0),
              decimal(paid[id] ?? 0),
              decimal(
                (s['total'] as int) - (returned[id] ?? 0) - (paid[id] ?? 0),
              ),
            ]);
          }
        }
        saved = await ExportFile.saveCsv(rows, 'SavdoYordam-$kind-$stamp.csv');
      }
      if (mounted && saved) message(context, 'exportSaved');
    } catch (_) {
      if (mounted) message(context, 'exportError');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.text;
    return Scaffold(
      appBar: AppBar(title: Text(s['export'])),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          NoticeCard(s['exportHint'], icon: Icons.download_outlined),
          const SizedBox(height: 20),
          for (final item in <({String key, String label, IconData icon})>[
            (
              key: 'products',
              label: 'products',
              icon: Icons.inventory_2_outlined,
            ),
            (key: 'customers', label: 'customers', icon: Icons.people_outline),
            (key: 'sales', label: 'sales', icon: Icons.receipt_long_outlined),
            (key: 'all', label: 'exportAll', icon: Icons.folder_copy_outlined),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AppCard(
                padding: 4,
                child: ListTile(
                  enabled: !busy,
                  leading: Icon(item.icon),
                  title: Text(s[item.label]),
                  subtitle: Text(item.key == 'all' ? 'JSON' : 'CSV'),
                  trailing: const Icon(Icons.download_outlined),
                  onTap: () => export(item.key),
                ),
              ),
            ),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
