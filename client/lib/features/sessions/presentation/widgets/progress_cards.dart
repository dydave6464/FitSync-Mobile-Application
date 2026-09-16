import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../../../core/widgets/fs_charts.dart';
import '../../domain/training_analytics.dart';
import '../../domain/strength_series.dart';

/// The hero. Adherence leads because it is the one number a beginner can act
/// on, and the only one that means anything in week one -- every trend on this
/// screen is still a single point then.
class AdherenceCard extends StatelessWidget {
  const AdherenceCard({super.key, required this.adherence, required this.window});

  final Adherence adherence;
  final String window;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return FsCard(
      accent: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FsEyebrow('Sessions'),
          const SizedBox(height: 6),
          Text(adherence.label, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          if (adherence.hasTarget) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: adherence.fraction,
                minHeight: 8,
                backgroundColor: t.surface2,
                color: t.accent,
              ),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            adherence.hasTarget
                ? 'of your plan in the $window'
                : 'completed in the $window',
            style: TextStyle(fontSize: 12, color: t.text3),
          ),
        ],
      ),
    );
  }
}

/// Volume, demoted from headline to trend. The total is meaningless -- nobody
/// has intuition for 48,200 kg -- so the percentage and the shape lead, and
/// the number is not shown at all.
class VolumeTrendCard extends StatelessWidget {
  const VolumeTrendCard({super.key, required this.analytics});

  final TrainingAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final buckets = analytics.volume;

    return FsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const FsEyebrow('Training volume'),
              if (analytics.change.hasChange) FsTag(analytics.change.label),
            ],
          ),
          const SizedBox(height: 8),
          FsLineChart(
            points: [
              for (var i = 0; i < buckets.length; i++)
                FsPoint(
                  x: i.toDouble(),
                  y: buckets[i].volumeKg,
                  label: buckets[i].label,
                ),
            ],
            // Volume starts at zero and belongs there: an untrained week IS
            // zero, so there is no noise to floor out.
            minYBand: 1,
          ),
        ],
      ),
    );
  }
}

/// Estimated 1RM. Two shapes, chosen by the server and captioned from
/// [StrengthSeries.xAxis] so the reader always knows which one they have.
class StrengthCard extends StatelessWidget {
  const StrengthCard({
    super.key,
    required this.series,
    required this.onPick,
  });

  final StrengthSeries series;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    if (series.points.isEmpty) {
      return FsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const FsEyebrow('Estimated 1RM'),
            const SizedBox(height: 6),
            Text(
              'Log a weighted set and this chart starts.',
              style: TextStyle(fontSize: 12, color: t.text3),
            ),
          ],
        ),
      );
    }

    final current = series.options.firstWhere(
      (o) => o.exerciseId == series.exerciseId,
      orElse: () => series.options.first,
    );

    return FsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const FsEyebrow('Estimated 1RM'),
              DropdownButton<int>(
                value: current.exerciseId,
                underline: const SizedBox.shrink(),
                style: TextStyle(fontSize: 12, color: t.text2),
                items: [
                  for (final o in series.options)
                    DropdownMenuItem(value: o.exerciseId, child: Text(o.name)),
                ],
                onChanged: (id) {
                  if (id != null) onPick(id);
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${series.points.last.e1rmKg.toStringAsFixed(1)} kg',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          FsLineChart(
            points: [
              for (var i = 0; i < series.points.length; i++)
                FsPoint(
                  x: i.toDouble(),
                  y: series.points[i].e1rmKg,
                  label: series.points[i].label,
                ),
            ],
            minYBand: kStrengthBandKg,
          ),
          const SizedBox(height: 6),
          Text(
            series.isSingleSession
                ? 'Today · by set'
                : 'Best set of each session',
            style: TextStyle(fontSize: 11, color: t.text3),
          ),
        ],
      ),
    );
  }
}
