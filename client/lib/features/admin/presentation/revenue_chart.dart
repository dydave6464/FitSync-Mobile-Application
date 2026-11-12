import 'package:flutter/material.dart';

import '../../../core/dates.dart' show monthShort;
import '../../../core/theme.dart';
import '../../../core/widgets/fs_charts.dart';
import '../domain/admin_format.dart';
import '../domain/admin_models.dart';

/// The Revenue tab's last six months: one bar a month, Pro at the bottom
/// and ads on top, each month's total above its bar and a legend naming
/// both parts, so colour is never the only clue.
class RevenueChart extends StatelessWidget {
  const RevenueChart({super.key, required this.months});

  /// Oldest first.
  final List<RevenueBar> months;

  static String _short(String ym) => monthShort[int.parse(ym.substring(5)) - 1];

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final spoken = [
      for (final m in months) '${_short(m.month)} ${formatPhp(m.totalPhp)}',
    ].join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              _Key(color: t.accentFill, name: 'Pro'),
              _Key(color: t.blue, name: 'Ads'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FsStackedBarChart(
          label: 'Revenue, last 6 months: $spoken',
          colors: [t.accentFill, t.blue],
          bars: [
            for (final m in months)
              FsStackedBar(
                values: [m.proPhp, m.adsPhp],
                label: _short(m.month)[0],
                total: formatPhp(m.totalPhp),
                tooltip:
                    '${monthLabel(m.month)}\n'
                    'Pro ${formatPhp(m.proPhp)} · Ads ${formatPhp(m.adsPhp)}',
              ),
          ],
        ),
      ],
    );
  }
}

/// A legend entry: the series' colour beside its name in the text ink.
class _Key extends StatelessWidget {
  const _Key({required this.color, required this.name});

  final Color color;
  final String name;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 6),
      Text(name, style: TextStyle(fontSize: 12, color: context.fs.text2)),
    ],
  );
}
