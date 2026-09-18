import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../core/units.dart';
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
    required this.unit,
  });

  final StrengthSeries series;
  final ValueChanged<int> onPick;

  /// `e1rmKg` is always kilograms from the server -- this is what the
  /// headline and chart are displayed in, mirroring [BodyWeightCard].
  final WeightUnit unit;

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
            formatWeightWithUnit(series.points.last.e1rmKg, unit),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          FsLineChart(
            points: [
              for (var i = 0; i < series.points.length; i++)
                FsPoint(
                  x: i.toDouble(),
                  y: convertFromKg(series.points[i].e1rmKg, unit),
                  label: series.points[i].label,
                ),
            ],
            minYBand: convertFromKg(kStrengthBandKg, unit),
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

/// Kilograms lifted per muscle group, as bars scaled against the biggest.
///
/// A Pro card, and the app's first: `isPremium` reached the client long
/// before anything read it. The server sends a free user no numbers at all,
/// so [TrainingAnalytics.musclesLocked] is what this renders from rather than
/// choosing not to draw data it was handed.
///
/// Three states, and the two empty ones are not the same: a locked card
/// offers the upgrade, while a Pro user who has logged nothing weighted is
/// told why their card is empty. Selling Pro to someone who already has it
/// would be the worse of the two mistakes.
class VolumeByMuscleCard extends StatelessWidget {
  const VolumeByMuscleCard({super.key, required this.analytics});

  final TrainingAnalytics analytics;

  /// The mockup's bar lengths, used only behind the lock. Fixed rather than
  /// random so the card does not shimmer on every rebuild, and unlabelled so
  /// nothing here can be mistaken for a reading.
  static const _placeholders = [0.82, 0.68, 0.45, 0.6];

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final locked = analytics.musclesLocked;

    return FsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The badge stays in every state: it is what says the feature
          // exists, which is the whole point of showing a locked card rather
          // than hiding it.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              FsEyebrow('Volume by muscle'),
              FsTag('Pro'),
            ],
          ),
          const SizedBox(height: 8),
          if (locked) ...[
            for (final fraction in _placeholders)
              FsBarRow(label: '', fraction: fraction, color: t.line2),
            const SizedBox(height: 8),
            Row(
              key: const Key('muscles.locked'),
              children: [
                Icon(Icons.lock_outline, size: 15, color: t.text3),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Unlock with Pro to see which muscles your volume goes to.',
                    style: TextStyle(fontSize: 11.5, color: t.text2, height: 1.4),
                  ),
                ),
              ],
            ),
          ] else if (analytics.muscles.isEmpty)
            Text(
              key: const Key('muscles.empty'),
              // Named plainly rather than left as an empty card: volume is
              // weight times reps, so a session of pull-ups and push-ups is
              // real work that this measure cannot see. See
              // readVolumeByMuscle in server/src/db/analytics.js.
              'Nothing lifted with weight in this window yet. Bodyweight sets '
              'count as training, but they carry no volume to chart.',
              style: TextStyle(fontSize: 12.5, color: t.text2, height: 1.4),
            )
          else
            for (final m in analytics.muscles)
              FsBarRow(label: m.muscle, fraction: analytics.muscleFraction(m)),
        ],
      ),
    );
  }
}
