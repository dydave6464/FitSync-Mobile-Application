import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../exercises/presentation/exercise_list_screen.dart';
import '../../plans/domain/split_style.dart';
import '../../plans/presentation/widgets/training_days_row.dart';
import '../../plans/domain/week_description.dart' show injuryLabel;
import '../../profile/domain/profile.dart';
import '../../profile/presentation/providers.dart';

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
  /// Which split this workout belongs to, named the way the generator names
  /// it -- one chip per rotation, so "Push / Pull / Legs" reads as the single
  /// choice it is rather than three.
  ///
  /// Not seeded from the active plan, unlike the generator's chips: the plan
  /// says what the week looks like, and this screen starts a single workout
  /// that need not be the next one in that rotation.
  String _splitStyle = splitStyles.first.value;

  /// The weekday whose profile write is in flight, if any.
  int? _savingWeekday;

  /// Writes the whole set, then lets the profile provider re-render the row.
  ///
  /// The same picker the generator and Settings carry, writing the same
  /// profile rows: which days you train is a fact about your week, so it is
  /// answerable from wherever the question arises rather than only from the
  /// screen that replaces your plan.
  ///
  /// Never optimistically ticked -- a failed write must not leave a day
  /// looking chosen.
  Future<void> _setTrainingDays(List<int> next, int tapped) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _savingWeekday = tapped);
    try {
      await ref.read(profileProvider.notifier).setTrainingDays(next);
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('Could not save your training days. ${describeError(error)}'),
      ));
    } finally {
      if (mounted) setState(() => _savingWeekday = null);
    }
  }

  /// Opens the library on the whole catalogue.
  ///
  /// The split deliberately does not narrow it. Constraining the catalogue to
  /// a whole split barely constrains it -- measured against the live
  /// catalogue, push_pull_legs left 997 of 1,203 exercises and upper_lower
  /// left the identical set, two chips that looked different and behaved the
  /// same. The filter chips and the search box are what narrow the list, and
  /// they narrow it to something the user chose rather than to something a
  /// chip implied.
  Future<void> _openLibrary() => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const ExerciseListScreen(selecting: true),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    // The AsyncValue, not `.value ?? const []`: PUT /profile/training-days
    // REPLACES the whole set, so a tap made against a row that is blank only
    // because the profile has not arrived would wipe the user's real days.
    // Only `hasValue` means the cells on screen are their actual answer.
    final asyncProfile = ref.watch(profileProvider);
    final daysKnown = asyncProfile.hasValue;
    final trainingDays = asyncProfile.value?.trainingDays ?? const <int>[];

    final injuries = asyncProfile.value?.injuries ?? const <SelectedInjury>[];
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
          const FsEyebrow('Split style'),
          const SizedBox(height: 10),
          Wrap(
            key: const Key('setup.splits'),
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final style in splitStyles)
                FsChip(
                  label: style.label,
                  selected: style.value == _splitStyle,
                  onTap: () => setState(() => _splitStyle = style.value),
                ),
            ],
          ),
          const SizedBox(height: 22),
          const FsEyebrow('Training days'),
          const SizedBox(height: 10),
          TrainingDaysRow(
            selected: trainingDays,
            enabled: daysKnown,
            busyWeekday: _savingWeekday,
            onChanged: (next) {
              // The tapped day is the one that differs between the two sets.
              final before = trainingDays.toSet();
              final after = next.toSet();
              final changed =
                  before.difference(after).followedBy(after.difference(before));
              if (changed.isEmpty) return;
              _setTrainingDays(next, changed.first);
            },
          ),
          if (!daysKnown) ...[
            const SizedBox(height: 8),
            Text(
              asyncProfile.hasError
                  ? "Couldn't load your training days. ${describeError(asyncProfile.error!)}"
                  : 'Loading your training days…',
              key: const Key('setup.trainingDays.unavailable'),
              style: TextStyle(fontSize: 12, color: t.text3, height: 1.35),
            ),
          ],
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
