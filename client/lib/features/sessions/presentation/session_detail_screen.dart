import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/numbers.dart';
import '../../../core/theme.dart';
import '../../../core/units.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../exercises/domain/exercise_labels.dart';
import '../../profile/presentation/providers.dart' show weightUnitProvider;
import '../domain/session_dates.dart';
import '../domain/session_detail.dart';
import '../domain/session_history.dart';
import 'providers.dart';

/// A finished workout, opened from its History row: what was trained, set by
/// set. Read-only -- there is nothing here to edit or delete.
class SessionDetailScreen extends ConsumerWidget {
  const SessionDetailScreen({
    super.key,
    required this.sessionId,
    required this.title,
  });

  final int sessionId;

  /// The row's own title, shown while the workout loads so the bar is never
  /// blank; the server's title replaces it once it arrives.
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.fs;
    final detail = ref.watch(sessionDetailProvider(sessionId));
    final unit = ref.watch(weightUnitProvider);

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(title: Text(detail.value?.title ?? title)),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => switch (error) {
          // Gone, or never yours: trying again would only be refused again.
          ApiException(code: 'SESSION_NOT_FOUND') => const _Gone(),
          _ => FsRetry(
            fullScreen: true,
            message: userMessage(error),
            onRetry: () => ref.invalidate(sessionDetailProvider(sessionId)),
          ),
        },
        data: (session) => _Body(session: session, unit: unit),
      ),
    );
  }
}

class _Gone extends StatelessWidget {
  const _Gone();

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Center(
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Text(
          "This workout isn't available any more.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, height: 1.45, color: context.fs.text2),
        ),
      ),
    ),
  );
}

class _Body extends StatelessWidget {
  const _Body({required this.session, required this.unit});

  final SessionDetail session;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        FsEyebrow(sessionDayLabel(session.sessionDate), maxLines: 2),
        const SizedBox(height: 4),
        Text(
          sessionFactsLine(
            setCount: session.setCount,
            totalVolumeKg: session.totalVolumeKg,
            durationMin: session.durationMin,
            unit: unit,
          ),
          style: TextStyle(fontSize: 13, color: t.text2),
        ),
        const SizedBox(height: 16),
        if (session.exercises.isEmpty)
          FsCard(
            child: Text(
              'No sets were logged in this workout.',
              style: TextStyle(fontSize: 13, height: 1.45, color: t.text2),
            ),
          )
        else
          for (final exercise in session.exercises) ...[
            _ExerciseCard(exercise: exercise, unit: unit),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({required this.exercise, required this.unit});

  final SessionDetailExercise exercise;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final equipment = exercise.equipment;
    final volume = exercise.volumeKg;

    return FsCard(
      key: Key('sessionDetail.exercise.${exercise.exerciseId}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              exerciseDisplayName(exercise.name),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: t.text,
              ),
            ),
          ),
          if (equipment != null) ...[
            const SizedBox(height: 2),
            Text(
              equipmentLabel(equipment),
              style: TextStyle(fontSize: 12, color: t.text2),
            ),
          ],
          const SizedBox(height: 10),
          for (final set in exercise.sets)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Set ${set.setNumber}',
                    style: TextStyle(fontSize: 13, color: t.text2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _setLine(set),
                      textAlign: TextAlign.end,
                      style: TextStyle(fontSize: 13, color: t.text),
                    ),
                  ),
                ],
              ),
            ),
          if (volume != null && volume > 0) ...[
            const SizedBox(height: 6),
            Text(
              '${groupThousands(convertFromKg(volume, unit))} ${unit.api}',
              semanticsLabel:
                  'Volume ${groupThousands(convertFromKg(volume, unit))} '
                  '${unit.api}',
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: t.text2,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// '60 kg × 8', '12 reps', '60 kg', or 'Done' when neither was recorded.
  String _setLine(SessionDetailSet set) {
    final kg = set.weightKg;
    final reps = set.reps;
    final weight = kg == null ? null : '${formatWeight(kg, unit)} ${unit.api}';
    return switch ((weight, reps)) {
      (final String w, final int r) => '$w × $r',
      (null, final int r) => '$r ${r == 1 ? 'rep' : 'reps'}',
      (final String w, null) => w,
      (null, null) => 'Done',
    };
  }
}
