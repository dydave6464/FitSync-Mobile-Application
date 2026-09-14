import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../exercises/presentation/exercise_list_screen.dart' show describeError;
import '../domain/session_history.dart';
import 'providers.dart';

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

  /// How far back the chosen window reaches, said plainly. The control says
  /// "Week" because that is what fits a segment; the card says what that
  /// actually means, because the windows are rolling rather than calendar.
  static const _windowLabel = {
    'week': 'last 7 days',
    'month': 'last 30 days',
    'year': 'last 365 days',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(trainingPeriodProvider);
    final summary = ref.watch(trainingSummaryProvider);
    final history = ref.watch(sessionHistoryProvider);

    void retry() {
      ref.invalidate(trainingSummaryProvider);
      ref.invalidate(sessionHistoryProvider);
    }

    // Either failing is an outage, and recovering one without the other
    // leaves half a screen that cannot be brought back without a restart.
    final error = summary.error ?? history.error;
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
        summary.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: CircularProgressIndicator()),
          ),
          // Unreachable: a failure was handled above. Kept because `when`
          // demands it, and a silent SizedBox would hide a future regression.
          error: (e, _) => _Retry(message: describeError(e), onRetry: retry),
          data: (totals) => _Totals(
            totals: totals,
            window: _windowLabel[period] ?? period,
          ),
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
                    for (final entry in page.sessions) _HistoryRow(entry: entry),
                  ],
                ),
        ),
      ],
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.totals, required this.window});

  final TrainingSummary totals;
  final String window;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FsCard(
          accent: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FsEyebrow('Total volume'),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                      groupThousands(totals.totalVolumeKg),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineMedium,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('kg', style: TextStyle(fontSize: 13, color: t.text2)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'lifted in the $window',
                style: TextStyle(fontSize: 12, color: t.text3),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _Tile(label: 'Sessions', value: '${totals.sessionCount}'),
            ),
            const SizedBox(width: 12),
            Expanded(child: _Tile(label: 'Sets', value: '${totals.setCount}')),
          ],
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return FsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: t.text3)),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final SessionHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    // A bodyweight-only session has no volume. "0 kg" would read as a failure
    // to record rather than as a fact about the workout, so it is left out.
    final facts = [
      '${entry.setCount} ${entry.setCount == 1 ? 'set' : 'sets'}',
      if (entry.totalVolumeKg != null && entry.totalVolumeKg! > 0)
        '${groupThousands(entry.totalVolumeKg!)} kg',
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
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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

/// 8053.0 -> "8,053". Whole kilos only: a gram of barbell volume is noise,
/// and the separator is what makes a five-figure total readable at a glance.
String groupThousands(double value) {
  final digits = value.round().toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}
