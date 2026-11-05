import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/amounts.dart';
import '../../core/strings.dart';
import '../../design_system/data_view.dart';
import '../../design_system/theme.dart';
import '../products/products_screen.dart';
import '../customers/customers_screen.dart';
import '../expenses/expenses_screen.dart';
import '../sales/sales_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(repositoryProvider);
    final s = context.text;
    return RefreshIndicator(
      onRefresh: () async {
        refreshData(ref);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  s['greeting'],
                  style: const TextStyle(color: muted, fontSize: 14),
                ),
              ),
              Text(
                DateFormat(
                  'dd.MM.yyyy',
                ).format(DateTime.now().toUtc().add(const Duration(hours: 5))),
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            repo.storeName,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 24),
          DataView(
            path: '/dashboard',
            builder: (data) {
              final d = data as Map;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppCard(
                    color: brand,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                s['todaySales'],
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.trending_up,
                              color: Colors.white70,
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Text(
                          money(d['sales'], repo.language),
                          style: Theme.of(context).textTheme.headlineLarge
                              ?.copyWith(color: Colors.white),
                        ),
                        const SizedBox(height: 20),
                        const Divider(color: Colors.white24),
                        const SizedBox(height: 16),
                        Text(
                          '${s['received']}\n${money(d['received'], repo.language)}',
                          style: const TextStyle(
                            color: Colors.white,
                            height: 1.6,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, constraints) => Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: MediaQuery.textScalerOf(context).scale(1) > 1.4
                              ? constraints.maxWidth
                              : (constraints.maxWidth - 12) / 2,
                          child: MetricCard(
                            label: s['debt'],
                            value: money(d['outstanding_debt'], repo.language),
                            icon: Icons.account_balance_wallet_outlined,
                          ),
                        ),
                        SizedBox(
                          width: MediaQuery.textScalerOf(context).scale(1) > 1.4
                              ? constraints.maxWidth
                              : (constraints.maxWidth - 12) / 2,
                          child: MetricCard(
                            label: s['saleCount'],
                            value: '${d['sale_count']}',
                            icon: Icons.receipt_long_outlined,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if ((d['low_stock'] as int) > 0) ...[
                    const SizedBox(height: 12),
                    AppCard(
                      padding: 4,
                      child: ListTile(
                        leading: const Icon(
                          Icons.inventory_2_outlined,
                          color: Color(0xFF835713),
                        ),
                        title: Text(s['lowStock']),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${d['low_stock']}'),
                            const SizedBox(width: 8),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: () => context.go('/products'),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
          SectionHeading(s['quickActions']),
          AppButton(
            label: s['newSale'],
            icon: Icons.add,
            onPressed: () => context.push('/pos'),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final action
                    in <({String label, IconData icon, VoidCallback onTap})>[
                      (
                        label: s['addProduct'],
                        icon: Icons.inventory_2_outlined,
                        onTap: () => addProduct(context, ref),
                      ),
                      (
                        label: s['addCustomer'],
                        icon: Icons.person_add_outlined,
                        onTap: () => addCustomer(context, ref),
                      ),
                      (
                        label: s['addExpense'],
                        icon: Icons.north_east_rounded,
                        onTap: () => addExpense(context, ref),
                      ),
                      (
                        label: s['debtSale'],
                        icon: Icons.account_balance_wallet_outlined,
                        onTap: () => context.push('/pos?credit=true'),
                      ),
                    ])
                  SizedBox(
                    width: MediaQuery.textScalerOf(context).scale(1) > 1.4
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 10) / 2,
                    child: _QuickAction(
                      label: action.label,
                      icon: action.icon,
                      onTap: action.onTap,
                    ),
                  ),
              ],
            ),
          ),
          SectionHeading(
            s['latestSales'],
            action: TextButton(
              onPressed: () => context.go('/sales'),
              child: Text(s['all']),
            ),
          ),
          DataView(
            path: '/sales',
            builder: (rows) {
              final list = (rows as List).take(5).toList();
              if (list.isEmpty) {
                return const EmptyState(icon: Icons.receipt_long_outlined);
              }
              return Column(
                children: list
                    .map((s) => SaleTile(sale: Map<String, dynamic>.from(s)))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: border),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: brand),
            const SizedBox(height: 12),
            Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    ),
  );
}
