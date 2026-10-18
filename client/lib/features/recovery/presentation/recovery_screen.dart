import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/units.dart';
import '../../../core/widgets/fs_charts.dart'
    show FsRing, FsBarChart, FsChartBar;
import '../../../core/widgets/fs_kit.dart' hide FsRing;
import '../../exercises/presentation/exercise_list_screen.dart'
    show describeError;
import '../../profile/presentation/providers.dart' show weightUnitProvider;
import '../../sessions/domain/training_analytics.dart' show VolumeBucket;
import '../../sessions/domain/volume_labels.dart'
    show volumeBucketName, volumeToday;
import '../../sessions/presentation/progress_screen.dart' show groupThousands;
import '../../sessions/presentation/widgets/share_report_sheet.dart'
    show formatShareExpiry;
import '../domain/recovery.dart';
import 'providers.dart';
import 'widgets/checkin_sheet.dart';
import 'widgets/how_to_read_sheet.dart';

/// The Recovery tab's body: the injury-risk ring with what it means and why,
/// what feeds it, and the 7-day training load beneath. Mirrors the loading
/// spinner and describeError + Retry treatment `PlanScreen` uses for its own
/// top-level provider, rather than inventing a third failure style.
class RecoveryScreen extends ConsumerWidget {
  const RecoveryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(recoveryOverviewProvider);

    return overview.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(describeError(error), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FsButton(
                label: 'Retry',
                small: true,
                onPressed: () => ref.invalidate(recoveryOverviewProvider),
              ),
            ],
          ),
        ),
      ),
      data: (data) => _RecoveryView(overview: data),
    );
  }
}

class _RecoveryView extends StatelessWidget {
  const _RecoveryView({required this.overview});

  final RecoveryOverview overview;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final estimate = overview.latestEstimate;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        FsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _EstimateHeader(),
              const SizedBox(height: 10),
              if (estimate == null)
                _EmptyEstimate(todayCheckin: overview.todayCheckin, t: t)
              else
                _EstimateCard(
                  estimate: estimate,
                  todayCheckin: overview.todayCheckin,
                  t: t,
                ),
              const SizedBox(height: 14),
              Text(
                'An estimate from your check-ins, training load and past '
                'injuries — not a medical diagnosis.',
                style: TextStyle(fontSize: 12, color: t.text2, height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FsCard(
          child: _FeedsScoreCard(overview: overview, t: t),
        ),
        if (overview.load.isNotEmpty) ...[
          const SizedBox(height: 12),
          FsCard(
            child: _LoadCard(load: overview.load, t: t),
          ),
        ],
        if (overview.muscles.isNotEmpty) ...[
          const SizedBox(height: 12),
          FsCard(
            key: const Key('recovery.muscles'),
            child: _MusclesCard(muscles: overview.muscles, t: t),
          ),
        ],
      ],
    );
  }
}

/// The card's eyebrow and its ⓘ, which opens the "How to read this" guide.
/// There with or without an estimate: someone deciding whether to check in
/// may want to know what they would get.
class _EstimateHeader extends StatelessWidget {
  const _EstimateHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: FsEyebrow('Injury-risk estimate')),
        IconButton(
          key: const Key('recovery.howToRead'),
          tooltip: 'How to read this',
          onPressed: () => showHowToReadSheet(context),
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          icon: Icon(Icons.info_outline, color: context.fs.text2),
        ),
      ],
    );
  }
}

class _EmptyEstimate extends StatelessWidget {
  const _EmptyEstimate({required this.todayCheckin, required this.t});

  final MorningCheckin? todayCheckin;
  final FsTokens t;

  @override
  Widget build(BuildContext context) {
    // Checked in but nothing came back -- the ML service was down when the
    // check-in was saved. Asking this person to check in again would be
    // wrong; an update re-sends the answers and tries the estimate again.
    return Text(
      todayCheckin == null
          ? 'Check in this morning to get your first estimate.'
          : 'Your check-in is saved, but no estimate came back. '
                'Tap Update below to try again.',
      key: const Key('recovery.empty'),
      style: TextStyle(fontSize: 13, color: t.text2, height: 1.4),
    );
  }
}

class _EstimateCard extends StatelessWidget {
  const _EstimateCard({
    required this.estimate,
    required this.todayCheckin,
    required this.t,
  });

  final InjuryRiskEstimate estimate;
  final MorningCheckin? todayCheckin;
  final FsTokens t;

  @override
  Widget build(BuildContext context) {
    final today = todayCheckin;
    // An estimate from today's check-in is dated by "today" already. Any
    // other is an earlier day's: none checked in yet, or today's was saved
    // while the ML service was down.
    final isToday = today != null && estimate.checkinDate == today.checkinDate;
    // An earlier day's ring is greyed, as Home's readiness ring is, so its
    // colour is not read as today's verdict.
    final color = !isToday
        ? t.text3
        : switch (estimate.riskLevel) {
            'high' => t.red,
            'moderate' => t.amber,
            _ => t.accent,
          };
    // The reasons, like the advice, held for the day they were worked out,
    // so an earlier day's greyed estimate shows neither.
    final why = isToday ? estimate.whyLine : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          // One phrase for a screen reader, which would otherwise hear the
          // bare word in the ring with nothing to say what it measures.
          child: Semantics(
            container: true,
            label: 'Injury risk: ${estimate.label}',
            excludeSemantics: true,
            child: FsRing(
              value: estimate.ringValue,
              color: color,
              child: Padding(
                padding: const EdgeInsets.all(14),
                // The ring is a fixed size while system text can double, so
                // the word shrinks to fit inside the stroke.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    estimate.label,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: t.text,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // The same score the other way up -- what Home's readiness ring
        // shows -- so the two screens can be read against each other, and
        // heard the same way too.
        if (estimate.readiness case final readiness?) ...[
          const SizedBox(height: 10),
          Semantics(
            container: true,
            label: 'Readiness $readiness out of 100',
            excludeSemantics: true,
            child: Text(
              'Readiness $readiness',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: t.text2,
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        // The level's advice holds for the day it was worked out, so an
        // earlier day's estimate says why there is none for today instead,
        // in Home's words.
        Text(
          isToday
              ? estimate.levelAdvice
              : (today == null
                    ? "Check in for today's estimate"
                    : "Today's estimate is unavailable"),
          key: const Key('recovery.advice'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            color: t.text,
            height: 1.35,
          ),
        ),
        if (!isToday) ...[
          const SizedBox(height: 4),
          Text(
            'From ${formatShareExpiry(DateTime.parse(estimate.checkinDate))}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: t.text2),
          ),
          // Today's check-in is saved but its estimate never came back: the
          // same way forward as when there is no older estimate to show.
          if (today != null) ...[
            const SizedBox(height: 8),
            Text(
              'Tap Update below to try again.',
              key: const Key('recovery.retry'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: t.text2, height: 1.4),
            ),
          ],
        ],
        if (why != null) ...[
          const SizedBox(height: 14),
          Text(
            why,
            key: const Key('recovery.why'),
            style: TextStyle(fontSize: 13.5, color: t.text, height: 1.4),
          ),
        ],
      ],
    );
  }
}

class _FeedsScoreCard extends ConsumerWidget {
  const _FeedsScoreCard({required this.overview, required this.t});

  final RecoveryOverview overview;
  final FsTokens t;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasToday = overview.todayCheckin != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FsEyebrow('What feeds this score'),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _Input(
                title: 'Morning check-in',
                detail:
                    'Sleep, soreness, energy and stress over the last 3 days',
                t: t,
              ),
            ),
            const SizedBox(width: 12),
            FsButton(
              key: Key(hasToday ? 'recovery.update' : 'recovery.checkin'),
              label: hasToday ? 'Update' : 'Check in',
              small: true,
              onPressed: () =>
                  showCheckinSheet(context, existing: overview.todayCheckin),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Input(
          title: 'Training load · 7 days',
          detail: 'This week compared with your usual week',
          t: t,
        ),
        const SizedBox(height: 12),
        _Input(
          title: 'Past injuries',
          detail: 'From your profile, and pain you report after a workout',
          t: t,
        ),
        const SizedBox(height: 14),
        Text(
          'Readiness is the same estimate the other way up: higher is better.',
          style: TextStyle(fontSize: 12, color: t.text2),
        ),
      ],
    );
  }
}

/// One input to the estimate: what it is, and what of it is read.
class _Input extends StatelessWidget {
  const _Input({required this.title, required this.detail, required this.t});

  final String title;
  final String detail;
  final FsTokens t;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontSize: 13.5, color: t.text)),
        const SizedBox(height: 2),
        Text(
          detail,
          style: TextStyle(fontSize: 12, color: t.text2, height: 1.35),
        ),
      ],
    );
  }
}

/// The last seven days' volume, a bar a day named by weekday, in the user's
/// weight unit. The server sends GET /recovery's `load` as the week period
/// of the volume summary, so its buckets are named as Progress names a week.
class _LoadCard extends ConsumerWidget {
  const _LoadCard({required this.load, required this.t});

  final List<VolumeBucket> load;
  final FsTokens t;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(weightUnitProvider);
    final today = volumeToday();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FsEyebrow('7-day training load'),
        const SizedBox(height: 14),
        FsBarChart(
          label: '7-day training load',
          bars: [for (var i = 0; i < load.length; i++) _bar(i, unit, today)],
        ),
      ],
    );
  }

  FsChartBar _bar(int index, WeightUnit unit, DateTime today) {
    final value = convertFromKg(load[index].volumeKg, unit);
    final name = volumeBucketName(
      period: 'week',
      index: index,
      count: load.length,
      fallback: load[index].label,
      today: today,
    );
    return FsChartBar(
      value: value,
      label: name.axis,
      tooltip: '${name.full} · ${groupThousands(value)} ${unit.api}',
    );
  }
}

/// When each muscle group was last trained, longest rested first. No
/// colours, bars or "recovered" labels: the app cannot measure recovery, so
/// it states the date and leaves the judgement to the person.
class _MusclesCard extends StatelessWidget {
  const _MusclesCard({required this.muscles, required this.t});

  final List<MuscleRecency> muscles;
  final FsTokens t;

  @override
  Widget build(BuildContext context) {
    final anyTrained = muscles.any((m) => m.daysAgo != null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FsEyebrow('Last trained'),
        const SizedBox(height: 12),
        if (!anyTrained)
          Text(
            'Finish a workout to see when each muscle group was last trained.',
            style: TextStyle(fontSize: 13, color: t.text2),
          )
        else
          for (final m in muscles)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      m.label,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: t.text,
                      ),
                    ),
                  ),
                  Text(
                    m.when,
                    style: TextStyle(fontSize: 12.5, color: t.text2),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
