import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/amounts.dart';
import '../../core/strings.dart';
import '../../design_system/data_view.dart';
import '../../design_system/theme.dart';
import '../sales/sales_screen.dart';

String auditTitle(Map event) {
  final path =
      (event['details'] as Map?)?['path'] as String? ??
      event['action'].toString();
  if (path.contains('/products/')) return 'editProduct';
  if (path.contains('/products')) return 'addProduct';
  if (path.contains('/inventory')) return 'adjustStock';
  if (path.contains('/return')) return 'processReturn';
  if (path.contains('/payments')) return 'repay';
  if (path.contains('/sales')) return 'sale';
  if (path.contains('/purchases')) return 'purchase';
  if (path.contains('/expenses')) {
    return path.endsWith('/void') ? 'voidExpense' : 'addExpense';
  }
  if (path.contains('/invitations')) return 'invitations';
  if (path.contains('/members')) return 'team';
  if (path.contains('/customers')) return 'addCustomer';
  if (path.contains('/offline')) return 'offlineMode';
  if (path.contains('/settings')) return 'storeInformation';
  return 'audit';
}

class AuditScreen extends ConsumerWidget {
  const AuditScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.text;
    return Scaffold(
      appBar: AppBar(title: Text(s['audit'])),
      body: DataView(
        path: '/audit',
        builder: (data) {
          final events = data as List;
          if (events.isEmpty) {
            return const SingleChildScrollView(
              child: EmptyState(icon: Icons.history),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: events.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final event = events[i] as Map;
              return AppCard(
                padding: 4,
                child: ListTile(
                  leading: const Icon(Icons.history_rounded),
                  title: Text(s[auditTitle(event)]),
                  subtitle: Text(
                    '${event['actor']}\n${displayDate(event['created_at'])}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (context) => _AuditDetails(event: event),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _AuditDetails extends StatelessWidget {
  const _AuditDetails({required this.event});
  final Map event;
  @override
  Widget build(BuildContext context) {
    final s = context.text;
    final details = event['details'] as Map? ?? {};
    final before = details['before'] as Map?;
    final after = details['after'] as Map?;
    final request = details['request'] as Map? ?? {};
    return AppSheet(
      title: s[auditTitle(event)],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${event['actor']} · ${displayDate(event['created_at'])}',
            style: const TextStyle(color: muted),
          ),
          const SizedBox(height: 16),
          if (after != null)
            Text(
              after['name'] ?? '',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          for (final field in [
            'price',
            'cost',
            'stock',
            'minimum_stock',
            'name',
            'sku',
            'category',
            'archived',
          ])
            if (after != null && after[field] != before?[field])
              SummaryRow(
                s[switch (field) {
                  'minimum_stock' => 'minimumStock',
                  'category' => 'productCategory',
                  _ => field,
                }],
                '${displayAuditValue(field, before?[field], s.locale.languageCode)} → ${displayAuditValue(field, after[field], s.locale.languageCode)}',
              ),
          if (request['amount'] != null)
            SummaryRow(
              s['amount'],
              money(request['amount'], s.locale.languageCode),
            ),
          if (request['reason'] != null)
            NoticeCard(request['reason'].toString(), icon: Icons.notes_rounded),
          if (details['resolution'] != null)
            NoticeCard(details['resolution'], warning: true),
        ],
      ),
    );
  }
}

String displayAuditValue(String field, dynamic value, String language) {
  if (value == null) return '—';
  if (field == 'price' || field == 'cost') return money(value as int, language);
  if (field == 'stock' || field == 'minimum_stock') {
    return quantity(value as int);
  }
  if (value is bool) return value ? '✓' : '—';
  return value.toString();
}
