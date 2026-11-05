import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/amounts.dart';
import '../../core/strings.dart';
import '../../design_system/theme.dart';

class AnalyticsCard extends StatefulWidget {
  const AnalyticsCard({super.key, required this.data});
  final Map data;
  @override
  State<AnalyticsCard> createState() => _AnalyticsCardState();
}

class _AnalyticsCardState extends State<AnalyticsCard> {
  int? selected;
  @override
  Widget build(BuildContext context) {
    final s = context.text;
    final daily = widget.data['daily'] as List? ?? [];
    final products = widget.data['products'] as List? ?? [];
    final index = (selected ?? (daily.length - 1))
        .clamp(0, math.max(0, daily.length - 1))
        .toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading(s['salesTrend']),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (daily.isEmpty)
                Text(s['empty'])
              else ...[
                Text(
                  daily[index]['date'],
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  money(daily[index]['net_sales'], s.locale.languageCode),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 20),
                Semantics(
                  label:
                      '${s['salesTrend']}: ${daily.map((d) => '${d['date']} ${money(d['net_sales'], s.locale.languageCode)}').join('; ')}',
                  child: LayoutBuilder(
                    builder: (context, constraints) => GestureDetector(
                      onTapDown: (tap) => setState(
                        () => selected =
                            (tap.localPosition.dx /
                                    constraints.maxWidth *
                                    daily.length)
                                .floor()
                                .clamp(0, daily.length - 1),
                      ),
                      child: SizedBox(
                        height: 120,
                        width: double.infinity,
                        child: CustomPaint(
                          painter: _TrendPainter(
                            values: daily
                                .map((d) => (d['net_sales'] as int).toDouble())
                                .toList(),
                            selected: index,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        daily.first['date'],
                        style: const TextStyle(color: muted, fontSize: 11),
                      ),
                    ),
                    Text(
                      daily.last['date'],
                      style: const TextStyle(color: muted, fontSize: 11),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              const Divider(),
              SummaryRow(
                s['previousPeriod'],
                money(
                  widget.data['previous_net_sales'] as int? ?? 0,
                  s.locale.languageCode,
                ),
              ),
            ],
          ),
        ),
        SectionHeading(s['topProducts']),
        AppCard(
          padding: 16,
          child: products.isEmpty
              ? Text(s['empty'], style: const TextStyle(color: muted))
              : Column(
                  children: [
                    for (final (i, p) in products.indexed)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${i + 1}'.padLeft(2, '0'),
                              style: const TextStyle(
                                color: muted,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p['name'],
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${quantity(p['quantity'])} ${s[p['unit']]}',
                                    style: const TextStyle(
                                      color: muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                money(p['total'], s.locale.languageCode),
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({required this.values, required this.selected});
  final List<double> values;
  final int selected;
  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final low = math.min(0.0, values.reduce(math.min));
    final high = math.max(0.0, values.reduce(math.max));
    final range = high - low;
    final denominator = range == 0 ? 1.0 : range;
    double y(double v) =>
        size.height - 8 - (v - low) / denominator * (size.height - 16);
    double x(int i) => values.length == 1
        ? size.width / 2
        : 8 + i * (size.width - 16) / (values.length - 1);
    final grid = Paint()
      ..color = border
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, y(0)), Offset(size.width, y(0)), grid);
    final path = Path()..moveTo(x(0), y(values.first));
    for (var i = 1; i < values.length; i++) {
      path.lineTo(x(i), y(values[i]));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = brand
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
    canvas.drawCircle(
      Offset(x(selected), y(values[selected])),
      6,
      Paint()..color = brand,
    );
    canvas.drawCircle(
      Offset(x(selected), y(values[selected])),
      3,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) =>
      old.values != values || old.selected != selected;
}
