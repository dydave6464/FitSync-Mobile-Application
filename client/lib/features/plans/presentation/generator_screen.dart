import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../exercises/presentation/exercise_list_screen.dart' show describeError;
import '../../onboarding/presentation/generating_view.dart';
import '../../profile/domain/profile.dart';
import '../../profile/presentation/providers.dart';
import '../domain/split_style.dart';
import '../domain/week_description.dart';
import '../domain/workout_plan.dart';
import 'providers.dart';
import 'widgets/training_days_row.dart';

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
  int? _savingWeekday;

  /// True once /regenerate has answered. Separate from [_busy], which flips
  /// before anything has been asked for: the building screen's last row
  /// claims the plan exists, so only this may tick it.
  bool _planReady = false;

  /// The building screen's lead row, captured when Generate is tapped rather
  /// than recomputed while it is up -- the plan is invalidated the moment the
  /// rebuild lands, and the row must go on describing what was actually sent.
  String _leadLabel = '';

  /// Writes the whole set, then lets the profile provider re-render the row.
  /// The cell is never optimistically ticked: a failed write must not leave a
  /// day looking chosen.
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

  /// Takes the resolved split/days/length the caller already has in scope
  /// rather than re-resolving from the provider -- `_buildControls` only
  /// runs in the data branch, so those values are the ones the user is
  /// actually looking at. Re-reading `activePlanProvider` here would revive
  /// the loading/error-flattening bug the debug getters still carry: a
  /// failed fetch reads null and falls back to full_body/3/45, and that
  /// fallback would go out as the generate payload.
  ///
  /// [replaceCustomPlan] is only ever true on the recursive call this makes
  /// to itself once the user has confirmed replacing a plan they built by
  /// hand -- see the CUSTOM_PLAN_WOULD_BE_LOST branch below. The server
  /// refuses that case by default rather than trusting this screen to warn,
  /// so the question is raised by the refusal itself: any other caller of
  /// regenerate is protected too, and this screen cannot forget to ask.
  Future<void> _generate(
    String split,
    int days,
    int length,
    List<int> trainingDays, {
    bool replaceCustomPlan = false,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    // Captured for the same reason as messenger and navigator above: regenerate
    // is the slowest call in the app and nothing blocks the user backing out
    // while it runs, so by the time the await below returns this State may
    // already be disposed. ref.invalidate would throw in that case -- the
    // container outlives the widget, so the refresh does too.
    final container = ProviderScope.containerOf(context, listen: false);
    // The building screen's first frame is the one this setState schedules,
    // so the hold below is measured from here.
    final since = DateTime.now();
    setState(() {
      _busy = true;
      _planReady = false;
      _leadLabel = _describeChoice(split, trainingDays, days);
    });
    try {
      await ref.read(planRepositoryProvider).regenerate(
            splitStyle: split,
            daysPerWeek: days,
            sessionLengthMin: length,
            replaceCustomPlan: replaceCustomPlan,
          );
      // The plan changed underneath every screen that reads it, so the whole
      // provider is invalidated rather than patched: the Plan tab re-reads and
      // renders the new day. Before the hold, so a user who backed out still
      // gets the refresh at the moment the request lands.
      container.invalidate(activePlanProvider);
      if (mounted) {
        // The last row describes this call; it may tick now, and the hold is
        // what gives the user time to see it do so. Held before the pop, not
        // after: the pop swaps this screen out, so a wait on the far side of
        // it would not be seen. Skipped when the user has already backed out
        // -- there is no list left to read.
        setState(() => _planReady = true);
        await GeneratingPace.regenerate.hold(since);
      }
      // Before the pop, and on the messenger captured above rather than one
      // looked up after it, so the message survives the screen leaving. The
      // "+" is global: generating from Home or Browse pops back to Home or
      // Browse, where the new plan is invisible and the only irreversible
      // action in this slice would otherwise finish with no evidence it
      // happened at all.
      messenger.showSnackBar(const SnackBar(content: Text('New plan generated')));
      if (mounted) navigator.pop();
    } on ApiException catch (error) {
      if (error.code != 'CUSTOM_PLAN_WOULD_BE_LOST') {
        if (!mounted) return;
        setState(() => _busy = false);
        messenger.showSnackBar(SnackBar(content: Text(error.message)));
        return;
      }
      // Reset before the dialog, not after: nothing has actually started
      // building yet, and the indeterminate spinner on the building screen
      // would otherwise spin behind the question for as long as it takes the
      // user to answer.
      if (!mounted) return;
      setState(() => _busy = false);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Replace your own plan?'),
          // The server's message names the plan and how many days it holds.
          // Rewording it here would mean keeping two copies of that sentence
          // in step.
          content: Text(error.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep my plan'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Replace it'),
            ),
          ],
        ),
      );
      // Backing out (confirmed == false or the dialog was dismissed) leaves
      // busy already reset above, and asks for nothing further -- the plan
      // the user built is untouched.
      if (confirmed == true && mounted) {
        // Recurses through this same method rather than re-sending the
        // request inline, so the confirmed attempt gets the identical busy
        // state and hold as the first -- there is exactly one place that
        // logic lives.
        await _generate(split, days, length, trainingDays, replaceCustomPlan: true);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('Something went wrong generating your plan. Try again.')),
      );
    }
  }

  /// The one place the fallback chain is written. Pure: two calls with the
  /// same plan and trainingDays always agree, so nothing needs to cache what
  /// a previous build computed for the debug getters below to stay honest.
  ({String split, int days, int length}) _resolve(
    WorkoutPlan? plan,
    List<int> trainingDays,
  ) =>
      (
        split: _splitStyle ?? plan?.splitStyle ?? _defaultSplit,
        // The chosen days are what the user just said; the plan's stored count
        // is a stale label until the next regeneration. Falling back to it
        // when nothing is chosen is what stops an empty schedule being sent.
        days: trainingDays.isNotEmpty
            ? trainingDays.length
            : (_daysPerWeek ?? plan?.daysPerWeek ?? _defaultDays),
        // Still resolved and still sent, even though nothing on this screen
        // sets it any more: omitting sessionLengthMin from the payload hands
        // the service's `overrides.sessionLengthMin || 45` a 60-minute plan
        // and silently shortens it. Removing the control must not change the
        // plan the user gets.
        length: plan?.sessionLengthMin ?? _defaultLength,
      );

  /// The lead row's sentence: what is actually being applied.
  ///
  /// Named days when there are any, because that is the choice the user made;
  /// a count only when there are none, because a count is then all there is
  /// to say.
  static String _describeChoice(String split, List<int> days, int count) {
    final label = splitStyles
        .firstWhere((s) => s.value == split,
            orElse: () => (value: split, label: describeSplit(split)))
        .label;
    if (days.isEmpty) {
      return '$label, $count day${count == 1 ? '' : 's'} a week';
    }
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '$label, ${(days.toList()..sort()).map((d) => names[d - 1]).join(' · ')}';
  }

  /// The injuries this plan is being built around, spelled as the catalogue
  /// spells them. Read in `build` rather than only in the controls: the
  /// building screen names them too, and it is on screen at the one moment
  /// the plan provider is mid-refetch.
  List<String> _avoidingNames() {
    final injuries =
        ref.watch(profileProvider).value?.injuries ?? const <SelectedInjury>[];
    final options =
        ref.watch(injuryOptionsProvider).value ?? const <InjuryOption>[];
    return [
      for (final selected in injuries)
        for (final option in options)
          if (option.injuryId == selected.injuryId)
            injuryLabel(option, selected),
    ];
  }

  // Read by the widget tests, which drive the controls and assert the state
  // they produce rather than reaching into private fields by name.
  String get debugSplitStyle => _resolve(
        ref.read(activePlanProvider).value,
        ref.read(profileProvider).value?.trainingDays ?? const [],
      ).split;
  int get debugDaysPerWeek => _resolve(
        ref.read(activePlanProvider).value,
        ref.read(profileProvider).value?.trainingDays ?? const [],
      ).days;
  int get debugSessionLengthMin => _resolve(
        ref.read(activePlanProvider).value,
        ref.read(profileProvider).value?.trainingDays ?? const [],
      ).length;

  @override
  Widget build(BuildContext context) {
    final asyncPlan = ref.watch(activePlanProvider);
    final avoiding = _avoidingNames();

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
      //
      // A rebuild takes the body over rather than spinning inside the button:
      // it is the same wait onboarding already explains, and a button that
      // has been busy for eight seconds says nothing about what is being
      // built. Checked ahead of `asyncPlan.when` deliberately -- the plan is
      // invalidated the instant the rebuild lands, and reading it first would
      // replace the finished checklist with a spinner just as its last row
      // ticks. Poppable, unlike onboarding's: nothing here is half-written,
      // and backing out of the slowest call in the app has always been
      // allowed.
      body: _busy
          ? GeneratingView(
              title: 'Rebuilding your plan…',
              subtitle: 'Matching exercises to your split, your equipment, '
                  'and your injuries.',
              leadLabel: _leadLabel,
              leadDone: true,
              avoiding: avoiding,
              planReady: _planReady,
              pace: GeneratingPace.regenerate,
              canPop: true,
            )
          : asyncPlan.when(
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
              data: (plan) => _buildControls(context, plan, avoiding),
            ),
    );
  }

  Widget _buildControls(
    BuildContext context,
    WorkoutPlan? plan,
    List<String> avoiding,
  ) {
    final t = context.fs;
    // The AsyncValue, for the reason the plan's is unwrapped above: the plan
    // can resolve while the profile has not, and `.value?.trainingDays ?? []`
    // reads identically for "loading", "failed" and "none chosen". Only the
    // last of those is an answer, and PUT /profile/training-days replaces the
    // whole set -- so a tap on a row that is blank because nothing arrived
    // sends one day and destroys the rest, with no undo.
    //
    // `hasValue` rather than a bare AsyncData check, so a refresh or a
    // failure that still carries the last good profile keeps the row live:
    // what it is showing then is real.
    final asyncProfile = ref.watch(profileProvider);
    final daysKnown = asyncProfile.hasValue;
    final trainingDays = asyncProfile.value?.trainingDays ?? const <int>[];
    final (:split, :days, :length) = _resolve(plan, trainingDays);

    // The AsyncValue, not `.value ?? const []`: that flattening reads the
    // same for "still loading", "failed" and "no regions exist", and the
    // describe card reports what it recognised -- so under a failed
    // catalogue it would state that nothing the user typed matched.
    final asyncOptions = ref.watch(injuryOptionsProvider);
    final options = asyncOptions.value ?? const <InjuryOption>[];

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
          // So the card can say when a day count it read has been overruled
          // by the picker below it. Still assigned to `_daysPerWeek` either
          // way -- it is what the fallback chain takes the moment the last
          // weekday is unticked -- but a value that changes nothing the user
          // can currently see has to be named rather than swallowed.
          trainingDays: trainingDays,
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
            for (final s in splitStyles)
              FsChip(
                label: s.label,
                selected: s.value == split,
                onTap: () => setState(() => _splitStyle = s.value),
              ),
          ],
        ),
        const SizedBox(height: 22),
        const FsEyebrow('Training days'),
        const SizedBox(height: 10),
        TrainingDaysRow(
          selected: trainingDays,
          busyWeekday: _savingWeekday,
          enabled: daysKnown,
          onChanged: (next) {
            // The tapped day is the one that differs between the two sets.
            // The row toggles exactly one, so there is always exactly one --
            // but `.first` on an empty difference throws a StateError, and
            // taking the whole screen down over two sets that merely matched
            // is not a trade worth leaving open.
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
                ? "Couldn't load your training days, so they can't be changed "
                    'here. ${describeError(asyncProfile.error!)}'
                : 'Loading your training days…',
            key: const Key('gen.trainingDays.unavailable'),
            style: TextStyle(
              fontSize: 12,
              color: asyncProfile.hasError ? t.red : t.text3,
              height: 1.35,
            ),
          ),
        ],
        // Session length is deliberately not shown. The service derives it
        // from goal and fitness level, so it is neither chosen here nor
        // changeable here, and a number on screen that the user cannot move
        // is one more thing to rule out. It is still resolved and still sent
        // -- see `_resolve`, where dropping it from the payload would hand
        // the service's own 45-minute default a 60-minute plan.
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
          // No in-button spinner: `_busy` takes the whole body over with the
          // building screen, so this button is not on screen to spin.
          onPressed: () => _generate(split, days, length, trainingDays),
        ),
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
    required this.trainingDays,
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

  /// The weekdays currently ticked below. Read only to decide whether a day
  /// count in the sentence has anywhere to land.
  final List<int> trainingDays;

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

    // The parser's topics plus the one only this screen can see. Recomputed
    // on every build rather than captured at Apply, because ticking a
    // weekday afterwards changes whether the count landed -- and a note that
    // went stale would be the same silent contradiction it exists to stop.
    final notes = [
      ...parsed.elsewhere,
      if (parsed.daysPerWeek != null && widget.trainingDays.isNotEmpty)
        WeekTopic.dayCount,
    ];

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

        if (notes.isNotEmpty)
          Padding(
            key: const Key('gen.describe.elsewhere'),
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              notes.map(_topicNote).join(' '),
              style: note,
            ),
          ),
      ],
    );
  }

  /// The domain reports a topic; the wording lives here.
  static String _topicNote(WeekTopic topic) => switch (topic) {
        WeekTopic.sessionLength =>
          'Session length follows your goal and fitness level, so it is not '
              'set here.',
        WeekTopic.goal => 'Your goal is set in your profile.',
        WeekTopic.dayCount =>
          'How many days you train follows the weekdays you have chosen '
              'below, so that count was not applied.',
      };
}
