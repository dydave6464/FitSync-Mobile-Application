import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../exercises/presentation/exercise_list_screen.dart';
import '../../exercises/presentation/providers.dart';
import '../../plans/domain/training_day.dart';
import '../../plans/domain/week_description.dart' show injuryLabel;
import '../../plans/presentation/providers.dart';
import '../../profile/domain/profile.dart';
import '../../profile/presentation/providers.dart';

/// What the service falls back to when a session carries no length override,
/// so a plan-less user is shown the length they would actually get.
const _defaultLength = 45;

/// The ML service's `EXERCISES_BY_SESSION`: how many exercises a session of a
/// given length is built from. Mirrored rather than fetched because nothing
/// serves it -- the counts arrive baked into a generated plan.
const _exercisesBySession = {45: 6, 60: 8};

/// How many exercises a [minutes]-long session aims for.
///
/// A plan's length is not required to be one of the two the table knows, so
/// it is snapped the way `_snap` in ml/app/rules/parameters.py snaps it:
/// nearest, and on a tie the shorter session, because a workout someone
/// finishes beats one they abandon. (No whole number actually ties -- the
/// midpoint is 52.5 -- but the rule is the service's, not a coincidence of
/// these two values.)
int _targetExercises(int minutes) {
  final snapped = _exercisesBySession.keys.reduce((best, known) {
    final nearer = (known - minutes).abs().compareTo((best - minutes).abs());
    return nearer < 0 || (nearer == 0 && known < best) ? known : best;
  });
  return _exercisesBySession[snapped]!;
}

/// What "Log manually" opens before the library.
///
/// Laid out like the generator minus the describe card, because the two
/// screens answer the same question about the same workout and a user who
/// has seen one should recognise the other. The controls differ in kind
/// though: nothing here replaces the plan, so this screen is a description of
/// the session about to be picked, not a payload.
class WorkoutSetupScreen extends ConsumerStatefulWidget {
  const WorkoutSetupScreen({super.key});

  @override
  ConsumerState<WorkoutSetupScreen> createState() => _WorkoutSetupScreenState();
}

class _WorkoutSetupScreenState extends ConsumerState<WorkoutSetupScreen> {
  /// Which day's worth of training this workout is.
  ///
  /// A day, not a split: a split is a rotation of days, and filtering the
  /// catalogue by a whole one barely filters -- push_pull_legs covers 997 of
  /// 1,203 live exercises and upper_lower covers the identical set. One day
  /// is 422.
  ///
  /// Not seeded from the active plan, unlike the generator's chips: the plan
  /// says what the week looks like, and this screen starts a single workout
  /// that need not be the next one in that rotation.
  TrainingDay _day = trainingDays.first;

  /// Narrows the catalogue to the chosen day for as long as the library is
  /// open, and no longer.
  ///
  /// Set and cleared here rather than inside the library: the Browse tab
  /// renders the same list from the same provider and stays mounted in the
  /// shell's IndexedStack, so a constraint left behind would silently narrow
  /// browsing to whatever day was last trained. Doing it in the library's own
  /// dispose is not an option -- that runs while the tree is being finalised,
  /// which is a build-phase provider write.
  Future<void> _openLibrary() async {
    final constraint = ref.read(catalogueConstraintProvider.notifier);
    constraint.set(_day.muscleGroups);
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const ExerciseListScreen(selecting: true),
    ));
    constraint.set(const []);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    // Loading and failure are NOT flattened into "no plan", even though
    // nothing here is sent anywhere. `.value` reads null for all three, and
    // only one of them means the fallback is true: having no plan yet. A
    // failed fetch would otherwise state a length and a target the screen
    // never read, about a plan the user does have -- and unlike the loading
    // case it never corrects itself. An em dash says "not known" honestly.
    final asyncPlan = ref.watch(activePlanProvider);
    final length = asyncPlan.hasValue
        ? (asyncPlan.value?.sessionLengthMin ?? _defaultLength)
        : null;

    final injuries = ref.watch(profileProvider).value?.injuries ?? const <SelectedInjury>[];
    final options = ref.watch(injuryOptionsProvider).value ?? const <InjuryOption>[];
    // Only regions the catalogue recognises, so a stale profile row cannot
    // put an unnamed injury on the card. Same derivation as the generator's.
    final avoiding = [
      for (final selected in injuries)
        for (final option in options)
          if (option.injuryId == selected.injuryId) injuryLabel(option, selected),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Log a workout')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          const FsEyebrow('Training today'),
          const SizedBox(height: 10),
          Wrap(
            key: const Key('setup.splits'),
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final day in trainingDays)
                FsChip(
                  label: day.label,
                  selected: day.label == _day.label,
                  onTap: () => setState(() => _day = day),
                ),
            ],
          ),
          const SizedBox(height: 22),
          // A readout, not a control, for the same reason it is one on the
          // generator: the service derives length from goal and fitness
          // level, so offering stops here would invite a choice nothing can
          // keep. Same label-and-value Row the generator pairs them in.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(child: FsEyebrow('Session length')),
              Text(
                length == null ? '—' : '$length min',
                key: const Key('setup.length.value'),
                style: fsNum(t).copyWith(color: t.accent),
              ),
            ],
          ),
          const SizedBox(height: 22),
          // Shown beside the length because it is the length's consequence:
          // the count is what the user is about to pick against in the
          // library, and deriving it silently would leave them guessing when
          // to stop adding rows.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(child: FsEyebrow('Target exercises')),
              Text(
                length == null ? '—' : '${_targetExercises(length)}',
                key: const Key('setup.target.value'),
                style: fsNum(t).copyWith(color: t.accent),
              ),
            ],
          ),
          if (avoiding.isNotEmpty) ...[
            const SizedBox(height: 22),
            FsCard(
              key: const Key('setup.avoiding'),
              child: Row(
                children: [
                  Icon(Icons.shield_outlined, size: 18, color: t.red),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      'Avoiding: ${avoiding.join(', ')}',
                      style: TextStyle(fontSize: 12, color: t.text2, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 22),
          FsButton(
            key: const Key('setup.select'),
            label: 'Select Exercise',
            // Pushed rather than replacing this route: backing out of the
            // library lands on the choices made here, not on whichever tab
            // the "+" sheet was opened from.
            onPressed: _openLibrary,
          ),
        ],
      ),
    );
  }
}
