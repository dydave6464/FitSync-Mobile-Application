import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/numbers.dart';
import '../../../core/theme.dart';
import '../../../core/units.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../exercises/presentation/exercise_list_screen.dart'
    show describeError;
import '../../profile/presentation/providers.dart'
    show bodyWeightProvider, weightUnitProvider;
import '../../profile/presentation/widgets/body_weight_card.dart';
import '../../profile/presentation/widgets/log_body_weight_sheet.dart';
import '../domain/session_history.dart';
import 'providers.dart';
import 'widgets/progress_cards.dart';
import 'widgets/share_report_sheet.dart';

/// What training has actually amounted to.
///
/// Replaces a "Coming soon" card that read "volume, sessions and personal
/// records appear here once you have logged a few workouts" -- which was
/// worse than saying nothing, because it blamed the user for an empty screen
/// that was never wired up. Someone who completed a workout, came back, and
/// still saw it reasonably concluded their session had not saved.
///
/// Personal records are deliberately absent rather than stubbed: a PR needs
/// per-exercise max-weight history and a definition of "new", and a wrong
/// number on a headline screen is worse than an honest omission.
class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  static const _periods = [
    (value: 'week', label: 'Week'),
    (value: 'month', label: 'Month'),
    (value: 'year', label: 'Year'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(trainingPeriodProvider);
    final analytics = ref.watch(trainingAnalyticsProvider(period));
    final summary = ref.watch(trainingSummaryProvider);
    final bodyWeight = ref.watch(bodyWeightProvider(period));
    final history = ref.watch(sessionHistoryProvider);
    final unit = ref.watch(weightUnitProvider);

    void retry() {
      ref.invalidate(trainingAnalyticsProvider(period));
      ref.invalidate(trainingSummaryProvider);
      ref.invalidate(bodyWeightProvider(period));
      ref.invalidate(sessionHistoryProvider);
    }

    // Only the analytics call earns a full-screen retry: it owns the period
    // every other card is scoped to, so without it the screen has no frame to
    // hang anything on. The sets and body weight cards render their own
    // inline error and their own retry, because either can fail while the
    // rest of the screen is perfectly readable.
    final error = analytics.error;
    if (error != null) {
      return _Retry(message: describeError(error), onRetry: retry);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        FsSegmented(
          options: _periods,
          selected: period,
          onSelected: (value) =>
              ref.read(trainingPeriodProvider.notifier).set(value),
        ),
        const SizedBox(height: 16),
        analytics.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: CircularProgressIndicator()),
          ),
          // Unreachable: a failure was handled above. Kept because `when`
          // demands it, and a silent SizedBox would hide a future regression.
          error: (e, _) => _Retry(message: describeError(e), onRetry: retry),
          data: (data) => VolumeTrendCard(analytics: data, unit: unit),
        ),
        const SizedBox(height: 12),
        // Side by side under the chart, as the prototype lays them out.
        // IntrinsicHeight because the two come from different fetches and
        // would otherwise settle at different heights as each lands.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: analytics.when(
                  loading: () => const _CardLoading(),
                  error: (e, _) =>
                      _Retry(message: describeError(e), onRetry: retry),
                  data: (data) => AdherenceCard(adherence: data.adherence),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: summary.when(
                  loading: () => const _CardLoading(),
                  error: (e, _) => _CardError(
                    message: describeError(e),
                    onRetry: () => ref.invalidate(trainingSummaryProvider),
                  ),
                  data: (data) => SetsCard(setCount: data.setCount),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        bodyWeight.when(
          loading: () => const _CardLoading(),
          error: (e, _) => _CardError(
            message: describeError(e),
            onRetry: () => ref.invalidate(bodyWeightProvider(period)),
          ),
          data: (data) => BodyWeightCard(
            series: data,
            unit: unit,
            onAdd: () => showLogBodyWeightSheet(context, period: period),
          ),
        ),
        const SizedBox(height: 12),
        // §5 of the design spec puts sets-by-muscle last of the analytics
        // cards, after body weight -- so it renders from its own `when` here
        // rather than inside `_AnalyticsCards` above, which now holds only
        // the two cards that lead the screen.
        analytics.when(
          loading: () => const _CardLoading(),
          // Unreachable: a failure was handled above. Kept because `when`
          // demands it, and a silent SizedBox would hide a future regression.
          error: (e, _) => _Retry(message: describeError(e), onRetry: retry),
          data: (data) => VolumeByMuscleCard(analytics: data),
        ),
        const SizedBox(height: 12),
        ShareWithCoachCard(
          onTap: () => showShareReportSheet(context, period: period),
        ),
        const SizedBox(height: 22),
        const FsEyebrow('Recent'),
        const SizedBox(height: 10),
        history.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => _Retry(message: describeError(e), onRetry: retry),
          data: (page) => page.sessions.isEmpty
              ? const _NothingYet()
              : Column(
                  children: [
                    for (final entry in page.sessions)
                      _HistoryRow(entry: entry, unit: unit),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Sets by muscle -- last of the analytics cards, per §5 of the design spec
/// The strength and body-weight cards' own loading placeholder -- shorter
/// than the analytics one above it, since these sit mid-list rather than
/// carrying the whole screen while empty.
class _CardLoading extends StatelessWidget {
  const _CardLoading();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 20),
    child: Center(child: CircularProgressIndicator()),
  );
}

/// A card-sized failure, for the strength and body-weight cards. Unlike
/// [_Retry], this does not take over the screen: either can fail while
/// everything around it stays readable, so its retry only refetches itself.
class _CardError extends StatelessWidget {
  const _CardError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return FsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: TextStyle(fontSize: 12, color: t.text3)),
          const SizedBox(height: 8),
          FsChip(label: 'Retry', selected: false, onTap: onRetry),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry, required this.unit});

  final SessionHistoryEntry entry;

  /// The volume is stored in kilograms; this is how it is read out, so a
  /// pound user's history agrees with the chart above it and the logger.
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    // A bodyweight-only session has no volume. "0 kg" would read as a failure
    // to record rather than as a fact about the workout, so it is left out.
    final facts = [
      '${entry.setCount} ${entry.setCount == 1 ? 'set' : 'sets'}',
      if (entry.totalVolumeKg != null && entry.totalVolumeKg! > 0)
        '${groupThousands(convertFromKg(entry.totalVolumeKg!, unit))} '
            '${unit.api}',
      if (entry.durationMin != null) '${entry.durationMin} min',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: FsCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(facts, style: TextStyle(fontSize: 12, color: t.text2)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              entry.sessionDate,
              style: TextStyle(fontSize: 11, color: t.text3),
            ),
          ],
        ),
      ),
    );
  }
}

class _NothingYet extends StatelessWidget {
  const _NothingYet();

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return FsCard(
      key: const Key('progress.empty'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No completed workouts yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Finish a workout and it will be listed here, with what you '
            'lifted and how long it took.',
            style: TextStyle(fontSize: 12.5, color: t.text2, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _Retry extends StatelessWidget {
  const _Retry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 40),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}
