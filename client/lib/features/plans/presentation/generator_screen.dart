import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../exercises/presentation/exercise_list_screen.dart' show describeError;
import '../../profile/domain/profile.dart';
import '../../profile/presentation/providers.dart';
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

/// "Knee (right)", or just "Lower back" where the region has no sides.
///
/// Laterality comes from the catalogue's `isLateral`, never from guessing
/// which regions have sides -- the same rule the onboarding step follows.
///
/// The side is parenthetical rather than a prefix, which is what keeps the
/// name exactly as the catalogue spells it: a prefix reads as a sentence
/// ("Left SI joint") and invites lowercasing the name to match, which
/// mangles every acronym and leaves "Left si joint" sitting next to a
/// non-lateral "Lower back" that kept its capital. It also gives 'both'
/// somewhere grammatical to go -- "Both shoulder" is not English.
///
/// A side this client does not recognise renders no side at all. Falling
/// back to one, as an if/else chain does by construction, names the wrong
/// side of the user's body with complete confidence on the one screen whose
/// job is saying what is being protected.
String _injuryLabel(InjuryOption option, SelectedInjury selected) {
  if (!option.isLateral || selected.side == null) return option.name;
  const labels = {'left': 'left', 'right': 'right', 'both': 'both sides'};
  final side = labels[selected.side];
  return side == null ? option.name : '${option.name} ($side)';
}

class GeneratorScreen extends ConsumerStatefulWidget {
  const GeneratorScreen({super.key});

  @override
  ConsumerState<GeneratorScreen> createState() => _GeneratorScreenState();
}

class _GeneratorScreenState extends ConsumerState<GeneratorScreen> {
  String? _splitStyle;
  int? _daysPerWeek;
  int? _sessionLengthMin;
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

    final injuries = ref.watch(profileProvider).value?.injuries ?? const <SelectedInjury>[];
    final options = ref.watch(injuryOptionsProvider).value ?? const <InjuryOption>[];
    final avoiding = [
      for (final selected in injuries)
        for (final option in options)
          if (option.injuryId == selected.injuryId) _injuryLabel(option, selected),
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
        const FsEyebrow('Session length'),
        const SizedBox(height: 10),
        FsSegmented(
          options: _lengths,
          selected: '$length',
          onSelected: (v) => setState(() => _sessionLengthMin = int.parse(v)),
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
