import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fs_charts.dart' show FsRing, FsBars, FsBar;
import '../../../core/widgets/fs_kit.dart' hide FsRing;
import '../../exercises/presentation/exercise_list_screen.dart'
    show describeError;
import '../../sessions/domain/training_analytics.dart' show VolumeBucket;
import '../../sessions/presentation/widgets/share_report_sheet.dart'
    show formatShareExpiry;
import '../domain/recovery.dart';
import 'providers.dart';
import 'widgets/checkin_sheet.dart';

/// The Recovery tab's body: the injury-risk ring, what feeds it, and the
/// 7-day training load beneath. Mirrors the loading spinner and
/// describeError + Retry treatment `PlanScreen` uses for its own top-level
/// provider, rather than inventing a third failure style.
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
          child: estimate == null
              ? _EmptyEstimate(t: t)
              : _EstimateCard(
                  estimate: estimate,
                  todayCheckin: overview.todayCheckin,
                  t: t,
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
      ],
    );
  }
}

class _EmptyEstimate extends StatelessWidget {
  const _EmptyEstimate({required this.t});

  final FsTokens t;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('recovery.empty'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FsEyebrow('Injury-risk estimate'),
        const SizedBox(height: 14),
        Text(
          'Check in this morning to get your first estimate.',
          style: TextStyle(fontSize: 13, color: t.text2, height: 1.4),
        ),
        const SizedBox(height: 12),
        Text(
          riskEstimateDisclaimer,
          style: TextStyle(fontSize: 11, color: t.text3, height: 1.4),
        ),
      ],
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
    final color = switch (estimate.riskLevel) {
      'high' => t.red,
      'moderate' => t.amber,
      _ => t.accent,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FsEyebrow('Injury-risk estimate'),
        const SizedBox(height: 14),
        Center(
          child: FsRing(
            value: estimate.ringValue,
            color: color,
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
        // Today's check-in already backs this estimate, so the day it came
        // from would only repeat what "today" already says.
        if (todayCheckin == null) ...[
          const SizedBox(height: 10),
          Center(
            child: Text(
              'From ${formatShareExpiry(DateTime.parse(estimate.checkinDate))}',
              style: TextStyle(fontSize: 11.5, color: t.text3),
            ),
          ),
        ],
        const SizedBox(height: 14),
        Text(
          riskEstimateDisclaimer,
          style: TextStyle(fontSize: 11, color: t.text3, height: 1.4),
        ),
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
              child: Text(
                'Morning check-in',
                style: TextStyle(fontSize: 13.5, color: t.text),
              ),
            ),
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
        Row(
          children: [
            Expanded(
              child: Text(
                'Training load · 7 days',
                style: TextStyle(fontSize: 13.5, color: t.text),
              ),
            ),
            Text(
              'From your logs',
              style: TextStyle(fontSize: 12, color: t.text3),
            ),
          ],
        ),
      ],
    );
  }
}

class _LoadCard extends StatelessWidget {
  const _LoadCard({required this.load, required this.t});

  final List<VolumeBucket> load;
  final FsTokens t;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FsEyebrow('7-day training load'),
        const SizedBox(height: 14),
        FsBars(
          bars: [
            for (final bucket in load)
              FsBar(label: bucket.label, value: bucket.volumeKg),
          ],
          color: t.accent,
        ),
      ],
    );
  }
}
