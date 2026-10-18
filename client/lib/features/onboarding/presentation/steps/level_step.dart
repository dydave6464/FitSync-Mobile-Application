import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../../exercises/presentation/exercise_list_screen.dart'
    show describeError;
import '../../../profile/domain/profile.dart';
import '../../../profile/presentation/providers.dart';

/// The answers step 3 collects.
class LevelAnswers {
  const LevelAnswers({
    this.fitnessLevel,
    this.equipmentIds = const [],
    this.trainingLocation,
    this.unfamiliar = false,
  });

  final String? fitnessLevel;

  /// The complete set the user owns. The server replaces this wholesale, so
  /// it is never a delta.
  final List<int> equipmentIds;

  final String? trainingLocation;

  /// Whether "I'm not familiar with any of these" is the choice on screen.
  /// UI state for this visit only, never saved: it is stored as Bodyweight
  /// alone, and reopening the step shows exactly that.
  final bool unfamiliar;

  LevelAnswers copyWith({
    String? fitnessLevel,
    List<int>? equipmentIds,
    String? trainingLocation,
    bool? unfamiliar,
  }) => LevelAnswers(
    fitnessLevel: fitnessLevel ?? this.fitnessLevel,
    equipmentIds: equipmentIds ?? this.equipmentIds,
    trainingLocation: trainingLocation ?? this.trainingLocation,
    unfamiliar: unfamiliar ?? this.unfamiliar,
  );
}

/// `fitness_level` ENUM values, gentlest first. There is no "advanced": the
/// app is for beginner and intermediate trainees.
const _levels = <({String value, String label})>[
  (value: 'new', label: 'New to training'),
  (value: 'beginner', label: 'Beginner'),
  (value: 'intermediate', label: 'Intermediate'),
];

/// What the chosen level does to the plan (ml/app/rules/parameters.py), in
/// words rather than numbers: the numbers also depend on the goal -- New and
/// Beginner both get 2 sets and 45 minutes for most goals -- and a copy of
/// them here would drift from the generator. A skipped level is planned as a
/// beginner, which is why that is the suggestion. No pointer to Settings:
/// this step is reused as the Settings editor.
String _levelHint(String? level) => switch (level) {
  'new' => 'The gentlest start: the fewest sets per exercise.',
  'beginner' => 'One set fewer than the standard plan.',
  'intermediate' => 'The full plan for your goal.',
  _ => 'Not sure? Pick Beginner.',
};

/// `training_location` ENUM values.
///
/// Behind a picker rather than on the step: the design gives location a
/// single row above the equipment, so it can pre-fill it, and so a second
/// chip strip cannot compete with the equipment set — the one place on this
/// step where chips mean "choose several".
const _locations = <({String value, String label})>[
  (value: 'home_gym', label: 'Home gym'),
  (value: 'commercial_gym', label: 'Commercial gym'),
  (value: 'both', label: 'Both'),
  (value: 'other', label: 'Somewhere else'),
];

/// What choosing a location pre-ticks, by equipment key. Null means every
/// chip except Bodyweight (see below for why). Applied only while nothing is
/// ticked, so it can save tapping but never undo a choice. Unlisted locations
/// pre-tick nothing.
///
/// Bodyweight is excluded from every list here except "other": the generator
/// (ml/app/main.py) unions body weight into `owned` unconditionally, so it is
/// already eligible for every user regardless of what is ticked. Ticking its
/// chip adds nothing eligible — it only moves body-weight exercises into the
/// "selected" ordering tier (ml/app/catalogue.py), where their low
/// exercise_ids put them ahead of the user's real equipment. Measured on the
/// dev DB: a home_gym pre-fill of dumbbell + band + body weight produced 3
/// body-weight / 2 band / 1 dumbbell exercises; dumbbell + band alone
/// produced 5 band / 1 dumbbell. "Other" is the one case where leading with
/// body weight is the intent: a user with no gym or home equipment should see
/// bodyweight work first.
const locationPrefill = <String, List<String>?>{
  'commercial_gym': null,
  'both': null,
  'home_gym': ['dumbbell', 'band'],
  'other': ['body weight', 'band', 'pull-up bar'],
};

/// Step 3: experience, equipment and where the training happens.
///
/// Reads the equipment lookup because that list belongs to the server, not to
/// the design — but still saves nothing and knows nothing about its scaffold.
class LevelStep extends ConsumerWidget {
  const LevelStep({super.key, required this.value, required this.onChanged});

  final LevelAnswers value;
  final ValueChanged<LevelAnswers> onChanged;

  void _toggleEquipment(int equipmentId) {
    // Ticking anything is a change of mind about "not familiar": the tick
    // just made is the whole selection, not an addition to Bodyweight.
    if (value.unfamiliar) {
      onChanged(value.copyWith(equipmentIds: [equipmentId], unfamiliar: false));
      return;
    }
    final next = [...value.equipmentIds];
    // remove() reports whether it was there, so this is one pass either way.
    if (!next.remove(equipmentId)) next.add(equipmentId);
    onChanged(value.copyWith(equipmentIds: next));
  }

  String get _locationLabel {
    for (final location in _locations) {
      if (location.value == value.trainingLocation) return location.label;
    }
    return 'Not set';
  }

  Future<void> _pickLocation(BuildContext context, WidgetRef ref) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            for (final location in _locations)
              ListTile(
                key: Key('location.${location.value}'),
                // The app theme insets tile content by 4dp, which reads as
                // padding only inside a card that brings its own. In a sheet
                // flush with the screen it puts the labels against the edge,
                // so this matches the 20dp the swap sheet uses.
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                title: Text(location.label),
                trailing: location.value == value.trainingLocation
                    ? Icon(Icons.check, size: 18, color: sheet.fs.accentText)
                    : null,
                onTap: () => Navigator.of(sheet).pop(location.value),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    var next = value.copyWith(trainingLocation: picked);
    if (value.equipmentIds.isEmpty && !value.unfamiliar) {
      next = next.copyWith(equipmentIds: _prefill(picked, ref));
    }
    onChanged(next);
  }

  List<int> _prefill(String location, WidgetRef ref) {
    if (!locationPrefill.containsKey(location)) return const [];
    final keys = locationPrefill[location];
    final options = ref.read(equipmentOptionsProvider).value ?? const [];
    return [
      for (final option in options)
        if (option.key != null &&
            (keys == null
                ? option.key != 'body weight'
                : keys.contains(option.key)))
          option.equipmentId,
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.fs;
    final theme = Theme.of(context);
    final equipment = ref.watch(equipmentOptionsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Your level & equipment', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 22),
        const FsEyebrow('Experience'),
        const SizedBox(height: 10),
        FsSegmented(
          options: _levels,
          selected: value.fitnessLevel,
          onSelected: (level) => onChanged(value.copyWith(fitnessLevel: level)),
        ),
        const SizedBox(height: 8),
        Text(
          _levelHint(value.fitnessLevel),
          key: const Key('level.hint'),
          style: TextStyle(fontSize: 12.5, color: t.text2),
        ),
        const SizedBox(height: 22),
        FsCard(
          key: const Key('trainingLocation'),
          small: true,
          onTap: () => _pickLocation(context, ref),
          child: Row(
            children: [
              Icon(Icons.home_outlined, size: 18, color: t.text2),
              const SizedBox(width: 11),
              const Expanded(
                child: Text(
                  'Training location',
                  style: TextStyle(fontSize: 13.5),
                ),
              ),
              Text(
                _locationLabel,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: value.trainingLocation == null ? t.text3 : t.text,
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, size: 16, color: t.text3),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Flexible(child: FsEyebrow('Available equipment')),
            FsTag(
              value.unfamiliar
                  ? 'Bodyweight only'
                  : '${value.equipmentIds.length} selected',
            ),
          ],
        ),
        // 8 of the 12 moved into each state below: the chips' band reaches
        // into the room above them only if that room is the rows' own.
        const SizedBox(height: 4),
        equipment.when(
          loading: () => const Padding(
            padding: EdgeInsets.fromLTRB(0, 32, 0, 24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Padding(
            padding: const EdgeInsets.fromLTRB(0, 24, 0, 16),
            child: Column(
              children: [
                Text(describeError(error), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FsButton(
                  label: 'Retry',
                  small: true,
                  kind: FsButtonKind.secondary,
                  onPressed: () => ref.invalidate(equipmentOptionsProvider),
                ),
              ],
            ),
          ),
          // The server now returns the curated list in display order, and
          // this step renders it verbatim.
          data: (options) => options.isEmpty
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'No equipment options are available right now.',
                    style: TextStyle(fontSize: 11, color: t.text3),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The room around the rows takes the outer chips' bands to
                    // 48 dp; the 8 above is this padding's.
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: FsTapRoom(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final option in options)
                              FsChip(
                                key: Key('equipment.${option.equipmentId}'),
                                label: option.name,
                                selected:
                                    !value.unfamiliar &&
                                    value.equipmentIds.contains(
                                      option.equipmentId,
                                    ),
                                showCheck: true,
                                onTap: () =>
                                    _toggleEquipment(option.equipmentId),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Builder(
                      builder: (context) {
                        EquipmentOption? bodyweight;
                        for (final option in options) {
                          if (option.key == 'body weight') {
                            bodyweight = option;
                          }
                        }
                        if (bodyweight == null) return const SizedBox.shrink();
                        final id = bodyweight.equipmentId;
                        return FsCard(
                          key: const Key('equipment.unfamiliar'),
                          small: true,
                          accent: value.unfamiliar,
                          selected: value.unfamiliar,
                          onTap: () => onChanged(
                            value.copyWith(
                              equipmentIds: [id],
                              unfamiliar: true,
                            ),
                          ),
                          child: Row(
                            children: [
                              FsRadioDot(selected: value.unfamiliar),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      "I'm not familiar with any of these",
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      "We'll start you on bodyweight exercises.",
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: t.text3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
