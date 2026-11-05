import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/amounts.dart';
import '../../core/strings.dart';
import '../../design_system/data_view.dart';
import '../../design_system/theme.dart';
import 'analytics_card.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});
  @override
  ConsumerState<ReportsScreen> createState() => _ReportsState();
}

class _ReportsState extends ConsumerState<ReportsScreen> {
  String period = 'today';
  DateTimeRange? custom;
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc().add(const Duration(hours: 5));
    final today = DateTime(now.year, now.month, now.day);
    final from = period == 'customPeriod' && custom != null
        ? custom!.start
        : today.subtract(
            Duration(
              days: switch (period) {
                'yesterday' => 1,
                'week' => 6,
                'month' => 29,
                _ => 0,
              },
            ),
          );
    final to = period == 'customPeriod' && custom != null
        ? custom!.end
        : period == 'yesterday'
        ? from
        : today;
    final dates =
        'from=${DateFormat('yyyy-MM-dd').format(from)}&to=${DateFormat('yyyy-MM-dd').format(to)}';
    final s = context.text;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      children: [
        PageHeading(s['reports'], subtitle: s['reportsHint']),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final p in [
                'today',
                'yesterday',
                'week',
                'month',
                'customPeriod',
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(s[p]),
                    selected: period == p,
                    onSelected: (_) async {
                      if (p == 'customPeriod') {
                        final value = await showDateRangePicker(
                          context: context,
                          initialDateRange:
                              custom ?? DateTimeRange(start: from, end: to),
                          firstDate: DateTime(2020),
                          lastDate: today,
                        );
                        if (value == null || !context.mounted) return;
                        if (value.end.difference(value.start).inDays > 366) {
                          message(context, 'invalid_period');
                          return;
                        }
                        setState(() {
                          custom = value;
                          period = p;
                        });
                      } else {
                        setState(() => period = p);
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${DateFormat('dd.MM.yyyy').format(from)} — ${DateFormat('dd.MM.yyyy').format(to)}',
          style: const TextStyle(color: muted),
        ),
        const SizedBox(height: 20),
        DataView(
          path: '/reports?$dates',
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
                      Text(
                        s['netSales'],
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        money(d['net_sales'], s.locale.languageCode),
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 16),
                      const Divider(color: Colors.white24),
                      const SizedBox(height: 8),
                      Text(
                        '${s['saleCount']}: ${d['sale_count']}',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
                SectionHeading(s['cashFlow']),
                AppCard(
                  padding: 18,
                  child: Column(
                    children: [
                      for (final e in {
                        'received': 'received',
                        'newDebt': 'new_debt',
                        'repaidDebt': 'repaid_debt',
                      }.entries)
                        SummaryRow(
                          s[e.key],
                          money(d[e.value], s.locale.languageCode),
                          strong: e.key == 'received',
                        ),
                    ],
                  ),
                ),
                SectionHeading(s['result']),
                AppCard(
                  padding: 18,
                  child: Column(
                    children: [
                      SummaryRow(
                        s['sales'],
                        money(d['sales'], s.locale.languageCode),
                      ),
                      SummaryRow(
                        s['returns'],
                        money(d['returns'], s.locale.languageCode),
                      ),
                      SummaryRow(
                        s['expenses'],
                        money(d['expenses'], s.locale.languageCode),
                      ),
                      const Divider(),
                      SummaryRow(
                        s['grossProfit'],
                        d['gross_profit'] == null
                            ? s['profitUnknown']
                            : money(d['gross_profit'], s.locale.languageCode),
                        strong: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AppCard(
                  color: const Color(0xFFFFF6E6),
                  padding: 18,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SummaryRow(
                        s['debt'],
                        money(d['outstanding_debt'], s.locale.languageCode),
                        strong: true,
                        color: amber,
                      ),
                      Text(
                        s['currentDebtHint'],
                        style: const TextStyle(color: amber, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        DataView(
          path: '/analytics?$dates',
          builder: (data) => AnalyticsCard(data: data as Map),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () => context.push('/expenses'),
          icon: const Icon(Icons.north_east_rounded),
          label: Text(s['expenses']),
        ),
      ],
    );
  }
}
