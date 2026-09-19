import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../core/units.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../../../core/widgets/fs_charts.dart';
import '../../domain/training_analytics.dart';

/// The hero. Adherence leads because it is the one number a beginner can act
/// on, and the only one that means anything in week one -- every trend on this
/// screen is still a single point then.
class AdherenceCard extends StatelessWidget {
  const AdherenceCard({super.key, required this.adherence});

  final Adherence adherence;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return FsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FsEyebrow('Sessions'),
          const SizedBox(height: 6),
          Text(adherence.label, style: Theme.of(context).textTheme.headlineSmall),
          if (adherence.hasTarget) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: adherence.fraction,
                minHeight: 8,
                backgroundColor: t.surface2,
                color: t.accent,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Sets logged in the window, beside [AdherenceCard].
///
/// The prototype pairs sessions with new personal records. PRs do not exist
/// here and are deliberately not stubbed (see ProgressScreen), so the pair is
/// filled with a number already fetched rather than an invented one: sets
/// come from `/sessions/summary`, which is scoped to the same window.
class SetsCard extends StatelessWidget {
  const SetsCard({super.key, required this.setCount});

  final int setCount;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return FsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FsEyebrow('Sets'),
          const SizedBox(height: 6),
          Text('$setCount', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text('logged', style: TextStyle(fontSize: 11, color: t.text3)),
        ],
      ),
    );
  }
}

/// Volume: the total lifted in the window, the change on the one before it,
/// and the shape it got there by.
///
/// The total used to be left off entirely, on the reasoning that nobody has
/// intuition for 48,200 kg. That is true of the raw figure and is an argument
/// about how to write the number rather than whether to show it --
/// [formatWeightCompact] is the answer, and a percentage with no total behind
/// it is the thinner half of the pair. It also leaves the first week blank:
/// with no previous window there is no percentage, so the card rendered a
/// shape with no number on it at all, which is the state every new account
/// opens in.
class VolumeTrendCard extends StatelessWidget {
  const VolumeTrendCard({
    super.key,
    required this.analytics,
    this.unit = WeightUnit.kg,
  });

  final TrainingAnalytics analytics;

  /// Everything on [analytics] is kilograms; this is how it is read out.
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final buckets = analytics.volume;

    return FsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Headline left, unit right, as the body-weight card below lays out
          // the same pair -- the two cards read as one family.
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const FsEyebrow('Training volume'),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          formatWeightCompact(analytics.change.totalKg, unit),
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        if (analytics.change.hasChange) ...[
                          const SizedBox(width: 8),
                          FsTag(analytics.change.label),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Text(
                '${unit.api} lifted',
                style: TextStyle(
                  fontFamily: fsMonoFamily,
                  fontSize: 11,
                  color: t.text3,
                ),
              ),
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

/// The way into the share sheet, at the foot of the Progress tab.
///
/// Accent-filled rather than a plain row: it is the only action on a screen
/// that is otherwise all readouts, and the prototype draws it that way.
class ShareWithCoachCard extends StatelessWidget {
  const ShareWithCoachCard({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return InkWell(
      key: const Key('progress.share'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(FsRadius.md),
      child: FsCard(
        accent: true,
        child: Row(
          children: [
            Icon(Icons.ios_share, size: 19, color: t.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Share with coach',
                    style: TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600, color: t.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'A link to this window, good for 30 days',
                    style: TextStyle(fontSize: 11.5, color: t.text3),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: t.text3),
          ],
        ),
      ),
    );
  }
}
