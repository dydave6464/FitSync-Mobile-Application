import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../exercises/presentation/exercise_list_screen.dart' show describeError;
import '../domain/workout_plan.dart';
import 'providers.dart';

/// The four split styles, and the labels the design gives them.
const _splits = <({String value, String label})>[
  (value: 'full_body', label: 'Full body'),
  (value: 'push_pull_legs', label: 'Push / Pull / Legs'),
  (value: 'upper_lower', label: 'Upper / Lower'),
  (value: 'cardio_core', label: 'Cardio + core'),
];

/// The generator knows two session lengths and snaps anything else, so the
/// control offers two stops rather than the prototype's slider. A slider
/// reading 50 would quietly build a 45-minute plan.
const _lengths = <({String value, String label})>[
  (value: '45', label: '45 min'),
  (value: '60', label: '60 min'),
];

const _defaultSplit = 'full_body';
const _defaultDays = 3;
const _defaultLength = 45;

class GeneratorScreen extends ConsumerStatefulWidget {
  const GeneratorScreen({super.key});

  @override
  ConsumerState<GeneratorScreen> createState() => _GeneratorScreenState();
}

class _GeneratorScreenState extends ConsumerState<GeneratorScreen> {
  String? _splitStyle;
  int? _daysPerWeek;
  int? _sessionLengthMin;

  /// The one place the fallback chain is written. Pure: two calls with the
  /// same plan always agree, so nothing needs to cache what a previous build
  /// computed for the debug getters below to stay honest.
  ({String split, int days, int length}) _resolve(WorkoutPlan? plan) => (
        split: _splitStyle ?? plan?.splitStyle ?? _defaultSplit,
        days: _daysPerWeek ?? plan?.daysPerWeek ?? _defaultDays,
        length: _sessionLengthMin ?? plan?.sessionLengthMin ?? _defaultLength,
      );

  // Read by the widget tests, which drive the controls and assert the state
  // they produce rather than reaching into private fields by name.
  String get debugSplitStyle =>
      _resolve(ref.read(activePlanProvider).value).split;
  int get debugDaysPerWeek =>
      _resolve(ref.read(activePlanProvider).value).days;
  int get debugSessionLengthMin =>
      _resolve(ref.read(activePlanProvider).value).length;

  @override
  Widget build(BuildContext context) {
    final asyncPlan = ref.watch(activePlanProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Workout Generator'),
        actions: const [
          Padding(padding: EdgeInsets.only(right: 16), child: Center(child: FsTag('Beta'))),
        ],
      ),
      // Loading and error both used to collapse into "no plan" -- plan?.x on
      // a null value reads the same whether the fetch is still in flight or
      // failed outright. That made a transient fetch failure show the
      // full_body/3/45 defaults under "Generating replaces your current
      // plan", so generating really would discard whatever plan the user
      // has. Both states are handled explicitly here, before the fallback
      // chain -- and therefore the controls -- ever runs.
      body: asyncPlan.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Couldn't load your current plan.", textAlign: TextAlign.center),
                const SizedBox(height: 6),
                Text(describeError(error), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FsButton(
                  label: 'Retry',
                  small: true,
                  kind: FsButtonKind.secondary,
                  onPressed: () => ref.invalidate(activePlanProvider),
                ),
              ],
            ),
          ),
        ),
        data: (plan) => _buildControls(context, plan),
      ),
    );
  }

  Widget _buildControls(BuildContext context, WorkoutPlan? plan) {
    final t = context.fs;
    final (:split, :days, :length) = _resolve(plan);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        const FsEyebrow('Split style'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in _splits)
              FsChip(
                label: s.label,
                selected: s.value == split,
                onTap: () => setState(() => _splitStyle = s.value),
              ),
          ],
        ),
        const SizedBox(height: 22),
        const FsEyebrow('Days / week'),
        const SizedBox(height: 10),
        _DaysRow(
          selected: days,
          onSelected: (d) => setState(() => _daysPerWeek = d),
        ),
        const SizedBox(height: 22),
        const FsEyebrow('Session length'),
        const SizedBox(height: 10),
        FsSegmented(
          options: _lengths,
          selected: '$length',
          onSelected: (v) => setState(() => _sessionLengthMin = int.parse(v)),
        ),
        const SizedBox(height: 22),
        Text(
          'Generating replaces your current plan.',
          style: TextStyle(fontSize: 12, color: t.text3, height: 1.4),
        ),
      ],
    );
  }
}

/// The 1-7 row, filled up to the selection as the prototype draws it.
class _DaysRow extends StatelessWidget {
  const _DaysRow({required this.selected, required this.onSelected});

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return Row(
      children: [
        for (var d = 1; d <= 7; d += 1) ...[
          if (d > 1) const SizedBox(width: 6),
          Expanded(
            child: InkWell(
              key: Key('gen.day.$d'),
              onTap: () => onSelected(d),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: d <= selected ? t.accent : t.surface2,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$d',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: d <= selected ? t.onAccent : t.text3,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
