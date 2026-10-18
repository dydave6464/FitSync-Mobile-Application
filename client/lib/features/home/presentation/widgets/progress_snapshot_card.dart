import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../core/units.dart';
import '../../../../core/widgets/fs_charts.dart' show FsBarChart;
import '../../../../core/widgets/fs_kit.dart';
import '../../../sessions/domain/session_history.dart';
import '../../../sessions/domain/training_analytics.dart';
import '../../../sessions/presentation/widgets/progress_cards.dart'
    show volumeBars;

/// Home's snapshot of training this month, opening the Progress tab.
///
/// Sessions, the chart and the volume change come from the same month
/// analytics Progress › Month shows, so the two never disagree. The new-PRs
/// count comes from the 30-day summary instead: it has no equivalent on
/// Progress to disagree with, and "new PRs" is counted by the server (best
/// estimated 1RM beating all earlier history) -- nothing here is derived on
/// the device.
class ProgressSnapshotCard extends StatelessWidget {
  const ProgressSnapshotCard({
    super.key,
    required this.summary,
    required this.analytics,
    required this.onTap,
    this.unit = WeightUnit.kg,
  });

  final TrainingSummary summary;
  final TrainingAnalytics analytics;
  final VoidCallback onTap;

  /// Everything on [analytics] is kilograms; this is how the bars are drawn.
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final change = analytics.change;

    return FsCard(
      key: const Key('home.progress'),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Your progress',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                  ),
                ),
              ),
              Text(
                'Past month',
                style: TextStyle(fontSize: 11.5, color: t.text3),
              ),
              Icon(Icons.chevron_right, size: 16, color: t.text3),
            ],
          ),
          const SizedBox(height: 8),
          if (analytics.adherence.done == 0)
            Text(
              'Finish a workout to see your progress here.',
              style: TextStyle(fontSize: 13, color: t.text2, height: 1.4),
            )
          else ...[
            // The Progress tab's bars in miniature, in the user's unit. No
            // axis words and no touch: the whole card is the way into the
            // full chart, and a tap here belongs to it.
            FsBarChart(
              label: 'Training volume this month',
              bars: volumeBars(analytics, unit, DateTime.now()),
              height: 52,
              showLabels: false,
              interactive: false,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _Stat(
                  valueKey: 'home.progress.sessions',
                  value: '${analytics.adherence.done}',
                  label: 'sessions',
                ),
                _Stat(
                  valueKey: 'home.progress.prs',
                  value: '${summary.newPrCount}',
                  label: 'new PRs',
                  divided: true,
                ),
                _Stat(
                  valueKey: 'home.progress.change',
                  // A first window has nothing to be up against; a
                  // percentage from zero is not a fact.
                  value: change.hasChange ? change.label : '—',
                  label: 'volume',
                  divided: true,
                  color: (change.changePct ?? 0) > 0 ? t.accent : null,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.valueKey,
    required this.value,
    required this.label,
    this.divided = false,
    this.color,
  });

  final String valueKey;
  final String value;
  final String label;
  final bool divided;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return Expanded(
      child: Container(
        padding: EdgeInsets.only(left: divided ? 12 : 0),
        decoration: divided
            ? BoxDecoration(
                border: Border(left: BorderSide(color: t.line)),
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              key: Key(valueKey),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: color ?? t.text,
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 10, color: t.text3)),
          ],
        ),
      ),
    );
  }
}
