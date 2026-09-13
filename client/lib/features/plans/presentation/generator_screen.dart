import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../exercises/presentation/exercise_list_screen.dart' show describeError;
import '../../profile/domain/profile.dart';
import '../../profile/presentation/providers.dart';
import '../domain/week_description.dart';
import '../domain/workout_plan.dart';
import 'providers.dart';

/// The four split styles, and the labels the design gives them.
const _splits = <({String value, String label})>[
  (value: 'full_body', label: 'Full body'),
  (value: 'push_pull_legs', label: 'Push / Pull / Legs'),
  (value: 'upper_lower', label: 'Upper / Lower'),
  (value: 'cardio_core', label: 'Cardio + core'),
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
  bool _busy = false;

  /// Takes the resolved split/days/length the caller already has in scope
  /// rather than re-resolving from the provider -- `_buildControls` only
  /// runs in the data branch, so those values are the ones the user is
  /// actually looking at. Re-reading `activePlanProvider` here would revive
  /// the loading/error-flattening bug the debug getters still carry: a
  /// failed fetch reads null and falls back to full_body/3/45, and that
  /// fallback would go out as the generate payload.
  Future<void> _generate(String split, int days, int length) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    // Captured for the same reason as messenger and navigator above: regenerate
    // is the slowest call in the app and nothing blocks the user backing out
    // while it runs, so by the time the await below returns this State may
    // already be disposed. ref.invalidate would throw in that case -- the
    // container outlives the widget, so the refresh does too.
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _busy = true);
    try {
      await ref.read(planRepositoryProvider).regenerate(
            splitStyle: split,
            daysPerWeek: days,
            sessionLengthMin: length,
          );
      // The plan changed underneath every screen that reads it, so the whole
      // provider is invalidated rather than patched: the Plan tab re-reads and
      // renders the new day.
      container.invalidate(activePlanProvider);
      // Before the pop, and on the messenger captured above rather than one
      // looked up after it, so the message survives the screen leaving. The
      // "+" is global: generating from Home or Browse pops back to Home or
      // Browse, where the new plan is invisible and the only irreversible
      // action in this slice would otherwise finish with no evidence it
      // happened at all.
      messenger.showSnackBar(const SnackBar(content: Text('New plan generated')));
      if (mounted) navigator.pop();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('Something went wrong generating your plan. Try again.')),
      );
    }
  }

  /// The one place the fallback chain is written. Pure: two calls with the
  /// same plan always agree, so nothing needs to cache what a previous build
  /// computed for the debug getters below to stay honest.
  ({String split, int days, int length}) _resolve(WorkoutPlan? plan) => (
        split: _splitStyle ?? plan?.splitStyle ?? _defaultSplit,
        days: _daysPerWeek ?? plan?.daysPerWeek ?? _defaultDays,
        // Still resolved and still sent, even though nothing on this screen
        // sets it any more: omitting sessionLengthMin from the payload hands
        // the service's `overrides.sessionLengthMin || 45` a 60-minute plan
        // and silently shortens it. Removing the control must not change the
        // plan the user gets.
        length: plan?.sessionLengthMin ?? _defaultLength,
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

    final injuries = ref.watch(profileProvider).value?.injuries ?? const <SelectedInjury>[];
    final options = ref.watch(injuryOptionsProvider).value ?? const <InjuryOption>[];
    final avoiding = [
      for (final selected in injuries)
        for (final option in options)
          if (option.injuryId == selected.injuryId) injuryLabel(option, selected),
    ];

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
        // Label and count on one line, as the mockup draws them and as
        // level_step.dart already pairs an eyebrow with its value. Seven
        // identical cells filled up to a boundary is a bar chart; the
        // number is the part a user can read without counting.
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Flexible(child: FsEyebrow('Days / week')),
            Text(
              '$days',
              key: const Key('gen.days.value'),
              style: fsNum(t).copyWith(color: t.accent),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _DaysRow(
          selected: days,
          onSelected: (d) => setState(() => _daysPerWeek = d),
        ),
        const SizedBox(height: 22),
        // A readout, not a control. The service derives length from goal and
        // fitness level and only honours an override so the prototype's
        // slider would not lie; offering stops here invited a choice it may
        // not keep. Shown rather than dropped because it is part of
        // describing the plan about to be replaced.
        //
        // Same shape as the days readout above, which is the pattern this
        // screen already uses for a label paired with its value.
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Flexible(child: FsEyebrow('Session length')),
            Text(
              '$length min',
              key: const Key('gen.length.value'),
              style: fsNum(t).copyWith(color: t.accent),
            ),
          ],
        ),
        if (avoiding.isNotEmpty) ...[
          const SizedBox(height: 22),
          FsCard(
            key: const Key('gen.avoiding'),
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
        Text(
          'Generating replaces your current plan.',
          style: TextStyle(fontSize: 12, color: t.text3, height: 1.4),
        ),
        const SizedBox(height: 18),
        FsButton(
          key: const Key('gen.generate'),
          label: 'Generate plan',
          busy: _busy,
          onPressed: () => _generate(split, days, length),
        ),
      ],
    );
  }
}

/// The 1-7 row, filled up to the selection as the prototype draws it.
class _DaysRow extends StatelessWidget {
  const _DaysRow({required this.selected, required this.onSelected});

  final int selected;

  /// Reports the COUNT a tap produces, not the cell that was tapped -- the
  /// two differ only on the lit top cell, and keeping the difference here
  /// keeps it beside the fill rule it mirrors.
  final ValueChanged<int> onSelected;

  /// Minimum days a plan can have. The service clamps to the same floor, so
  /// stepping below it would promise something the generator will not build.
  static const int _minDays = 1;

  /// A row filled 1..N reads as one boundary, so the only cell a tap can
  /// sensibly "unfill" is the boundary itself: tapping the count gives a day
  /// back. Every lower cell still selects outright -- tapping 2 when 4 is
  /// chosen means 2, not 1.
  int _countFor(int tapped) =>
      tapped == selected ? (tapped - 1).clamp(_minDays, tapped) : tapped;

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
              onTap: () => onSelected(_countFor(d)),
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
