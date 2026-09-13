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
    // The AsyncValue, not `.value ?? const []`: that flattening reads the
    // same for "still loading", "failed" and "no regions exist", and the
    // describe card reports what it recognised -- so under a failed
    // catalogue it would state that nothing the user typed matched.
    final asyncOptions = ref.watch(injuryOptionsProvider);
    final options = asyncOptions.value ?? const <InjuryOption>[];
    final avoiding = [
      for (final selected in injuries)
        for (final option in options)
          if (option.injuryId == selected.injuryId) injuryLabel(option, selected),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        _DescribeCard(
          key: const Key('gen.describe'),
          // Rebuilt from scratch whenever the plan or profile it describes
          // changes, so a sentence the user has not touched never describes a
          // plan they no longer have.
          composed: composeWeekDescription(
            profile: ref.watch(profileProvider).value,
            plan: plan,
            options: options,
          ),
          options: options,
          catalogueFailed: asyncOptions.hasError,
          onApply: (parsed) => setState(() {
            // Only what the sentence actually resolved. Assigning a null
            // through would reset a control the user set by hand to the
            // fallback chain's default, which is the one thing a vague
            // sentence must not do.
            _splitStyle = parsed.splitStyle ?? _splitStyle;
            _daysPerWeek = parsed.daysPerWeek ?? _daysPerWeek;
          }),
        ),
        const SizedBox(height: 22),
        const FsEyebrow('Split style'),
        const SizedBox(height: 10),
        Wrap(
          key: const Key('gen.splits'),
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


/// The prototype's "Describe your week" card.
///
/// Everything it understands lands in the controls below it, where the user
/// can see and correct it before generating. Nothing here reaches the
/// generator directly: the payload carries the controls, not this sentence.
class _DescribeCard extends ConsumerStatefulWidget {
  const _DescribeCard({
    super.key,
    required this.composed,
    required this.options,
    required this.catalogueFailed,
    required this.onApply,
  });

  /// The sentence "From profile" writes, composed from the live profile and
  /// plan.
  final String composed;

  final List<InjuryOption> options;

  /// Whether the injury catalogue failed to load. Distinct from an empty
  /// catalogue: one means "nothing matched", the other means "nothing could
  /// be checked", and only one of those is safe to say.
  final bool catalogueFailed;

  final ValueChanged<WeekDescription> onApply;

  @override
  ConsumerState<_DescribeCard> createState() => _DescribeCardState();
}

class _DescribeCardState extends ConsumerState<_DescribeCard> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.composed);

  /// The last applied parse, or null before the first Apply. Held so the
  /// offers and notes below the field survive rebuilds without re-parsing
  /// text the user may have edited since.
  WeekDescription? _applied;

  /// Regions the user has dismissed by adding them, kept so the offer goes
  /// away the moment the write succeeds rather than waiting for the profile
  /// to come back round.
  final Set<int> _added = {};

  int? _adding;

  @override
  void didUpdateWidget(_DescribeCard old) {
    super.didUpdateWidget(old);
    // The profile is fetched separately from the plan, so the first build of
    // this card routinely happens before there is a goal to write about. The
    // box has to follow what it describes until the user takes it over --
    // comparing against the PREVIOUS sentence is what tells those apart:
    // still untouched means still ours to fill, edited means hands off.
    if (widget.composed != old.composed && _controller.text == old.composed) {
      _controller.text = widget.composed;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _apply() {
    final parsed = parseWeekDescription(_controller.text, widget.options);
    setState(() => _applied = parsed);
    widget.onApply(parsed);
  }

  Future<void> _add(SelectedInjury injury) async {
    final messenger = ScaffoldMessenger.of(context);
    final current = ref.read(profileProvider).value?.injuries ?? const <SelectedInjury>[];
    setState(() => _adding = injury.injuryId);
    try {
      // PUT /profile/injuries replaces the whole set, so the existing
      // injuries go back with it. Sending only the new region would delete
      // every other injury the user has.
      await ref.read(profileProvider.notifier).setInjuries([...current, injury]);
      if (!mounted) return;
      setState(() {
        _added.add(injury.injuryId);
        _adding = null;
      });
    } catch (error) {
      if (!mounted) return;
      // The offer stays: nothing was saved, so nothing should look saved.
      setState(() => _adding = null);
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    }
  }

  /// Regions the sentence named that the profile does not already carry.
  List<({InjuryOption option, SelectedInjury injury})> get _offers {
    final parsed = _applied;
    if (parsed == null) return const [];
    final held = {
      for (final i in ref.watch(profileProvider).value?.injuries ?? const <SelectedInjury>[])
        i.injuryId,
    };

    return [
      for (final injury in parsed.injuries)
        if (!held.contains(injury.injuryId) && !_added.contains(injury.injuryId))
          for (final option in widget.options)
            if (option.injuryId == injury.injuryId)
              (option: option, injury: injury),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final parsed = _applied;

    return FsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FsEyebrow('Describe your week'),
          const SizedBox(height: 8),
          FsField(
            key: const Key('gen.describe.field'),
            controller: _controller,
            hint: 'e.g. full body, 4 days a week, protecting my lower back',
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FsChip(
                key: const Key('gen.describe.apply'),
                label: 'Apply',
                selected: true,
                onTap: _apply,
              ),
              FsChip(
                key: const Key('gen.describe.fromProfile'),
                label: 'From profile',
                selected: false,
                onTap: () => setState(() {
                  _controller.text = widget.composed;
                  _applied = null;
                  _added.clear();
                }),
              ),
            ],
          ),
          if (parsed != null) ...[
            const SizedBox(height: 12),
            _result(t, parsed),
          ],
        ],
      ),
    );
  }

  Widget _result(FsTokens t, WeekDescription parsed) {
    final note = TextStyle(fontSize: 12, color: t.text3, height: 1.35);

    return Column(
      key: const Key('gen.describe.result'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (parsed.isEmpty && !widget.catalogueFailed)
          Text("Nothing in that changed your plan -- the controls below are "
              "unchanged.", style: note),

        // Said whatever else was parsed: the catalogue is what injury
        // matching depends on, so without it "no regions matched" is a claim
        // this card cannot support.
        if (widget.catalogueFailed)
          Padding(
            key: const Key('gen.describe.catalogueError'),
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              "Couldn't check that against your injuries. Anything you wrote "
              'about them has been left alone.',
              style: note.copyWith(color: t.red),
            ),
          ),

        for (final offer in _offers)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Icon(Icons.shield_outlined, size: 16, color: t.red),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    // Names the consequence, not the database state. Whether a
                    // row exists in the profile is not what the user is
                    // deciding; whether their plan stops loading the region
                    // is, and only the profile drives that -- /regenerate
                    // reads injuries server-side and never from this screen.
                    '${injuryLabel(offer.option, offer.injury)} '
                    'is not in your injuries. Add it and every plan from now '
                    'on will skip the exercises that load it.',
                    style: note,
                  ),
                ),
                const SizedBox(width: 8),
                FsButton(
                  key: Key('gen.describe.add.${offer.option.injuryId}'),
                  label: 'Add',
                  small: true,
                  kind: FsButtonKind.secondary,
                  busy: _adding == offer.option.injuryId,
                  onPressed: () => _add(offer.injury),
                ),
              ],
            ),
          ),

        if (parsed.elsewhere.isNotEmpty)
          Padding(
            key: const Key('gen.describe.elsewhere'),
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              parsed.elsewhere.map(_topicNote).join(' '),
              style: note,
            ),
          ),
      ],
    );
  }

  /// The domain reports a topic; the wording lives here.
  static String _topicNote(WeekTopic topic) => switch (topic) {
        WeekTopic.sessionLength =>
          'Session length follows your plan, so it is shown rather than chosen.',
        WeekTopic.goal => 'Your goal is set in your profile.',
      };
}
