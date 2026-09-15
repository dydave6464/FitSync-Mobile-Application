import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/theme.dart';
import '../../../core/units.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../exercises/presentation/providers.dart'
    show exerciseRepositoryProvider;
import '../../exercises/presentation/exercise_list_screen.dart' show describeError;
import '../../plans/domain/workout_plan.dart';
import '../../plans/presentation/add_to_plan_sheet.dart';
import '../../plans/presentation/providers.dart';
import '../../profile/presentation/providers.dart';
import '../domain/active_session.dart';
import 'in_session_exercise_screen.dart';
import 'providers.dart';
import 'widgets/exercise_demo_stage.dart';
import 'widgets/exercise_jump_sheet.dart';
import 'widgets/exercise_log_panel.dart';
import 'widgets/logger_action.dart';
import 'widgets/rest_timer.dart';
import 'widgets/set_drafts.dart';
import 'workout_draft.dart' show chosenSplitStyleProvider;

/// The active workout, one exercise at a time: its set table, Continue to
/// the next, and the jump sheet for anything out of order.
class SessionLoggerScreen extends ConsumerStatefulWidget {
  const SessionLoggerScreen({super.key});

  @override
  ConsumerState<SessionLoggerScreen> createState() => _SessionLoggerScreenState();
}

/// Which face of the current exercise is on screen. Two faces of one
/// exercise, which is why this is a field and not a second route: the
/// session, the rest countdown and the draft store all live in the State
/// below, and a pushed route would have to be handed every one of them.
enum _LoggerStage { demo, logging }

class _SessionLoggerScreenState extends ConsumerState<SessionLoggerScreen> {
  static const _restDuration = Duration(seconds: 90);

  /// Which exercise is on screen.
  ///
  /// Read through a clamp rather than corrected on write: the active plan can
  /// change under a resumed session, and an index left past the end of a
  /// shortened plan would throw on the next build.
  int _index = 0;

  /// Which face of [_index]'s exercise is showing. Demo first: this
  /// initialiser is what opens the workout on the first exercise's demo, and
  /// every later move sets it explicitly at the point the move is made.
  _LoggerStage _stage = _LoggerStage.demo;

  bool _resting = false;

  /// One store per exercise on screen. Rebuilt when the exercise changes, so
  /// a set number means one thing at a time.
  SetDrafts _drafts = SetDrafts();
  int _draftsForIndex = 0;

  /// The unit last confirmed on screen -- i.e. actually read back from
  /// [weightUnitProvider], not merely requested. Null until the first build
  /// that reaches the set table, so the very first frame never "converts"
  /// against nothing, and a unit confirmed while the screen is still loading
  /// (or sitting on an empty day) converts once there is a store to convert.
  ///
  /// Converting against this rather than in `_setUnit` itself means a
  /// failed profile write leaves the typed text alone: the display stays on
  /// the old unit, and so does whatever was typed under it, until the write
  /// actually lands and this unit changes for real.
  WeightUnit? _unitOnScreen;

  /// Swaps the store when the exercise changes. Called from build, which is
  /// the only place that knows the clamped index.
  ///
  /// One job, deliberately. Resetting [_stage] from here as well would tie the
  /// stage to the store's lifetime, and the back handler would then need the
  /// early return below to keep the table it is stepping back to -- which
  /// skips the swap too, and hands the previous exercise the kg and reps typed
  /// against this one. Stage is an outcome of navigation, so every move sets
  /// it where the move is made.
  void _syncDrafts(int index) {
    if (index == _draftsForIndex) return;
    _drafts.dispose();
    _drafts = SetDrafts();
    _draftsForIndex = index;
  }

  @override
  void dispose() {
    _drafts.dispose();
    super.dispose();
  }

  /// The session as last seen from the controller.
  ///
  /// complete() and abandon() clear the controller the moment the server
  /// confirms, but this screen stays mounted until its route pops -- with the
  /// summary dialog sitting over it. Falling back to the loading spinner in
  /// that gap would flash a loading screen behind the summary of a workout
  /// that has just finished, so the last session seen is kept and rendered
  /// until the route goes away.
  ActiveSession? _lastSeenSession;

  /// Guards Finish against a second tap landing while the first request is
  /// still in flight. Without it, a second call would reach the controller's
  /// complete() a second time -- either double-dispatching to the server, or,
  /// once the first has resolved and cleared the session, hitting the
  /// controller's _current getter and throwing a raw StateError.
  bool _finishing = false;

  /// Clamped, because [startedAt] is the SERVER's NOW() while [DateTime.now]
  /// is the phone's. A phone clock behind the server makes the difference
  /// negative, and POST /complete rejects a negative durationMin with
  /// 400 DURATION_INVALID -- the one failure mode where a session genuinely
  /// cannot be finished from the phone. The upper bound is the route's own.
  ///
  /// The clamp is a guard, not a correction, and it hid a real defect for a
  /// while: the server was sending startedAt eight hours in the future on a
  /// UTC+8 host, so every workout read "0 min elapsed" and every completed
  /// session stored durationMin 0. That was a server-side timezone bug --
  /// see SESSION_COLUMNS in src/db/sessions.js -- and is fixed there. A
  /// clamp that silently swallows a whole class of wrong answers is worth
  /// being suspicious of when the number it produces is always the bound.
  int _elapsedMinutes(DateTime? startedAt) {
    if (startedAt == null) return 0;
    return DateTime.now().difference(startedAt).inMinutes.clamp(0, 1440);
  }

  /// The session was closed by someone/something else -- another device, an
  /// earlier tap whose response was lost, or a second Finish/Discard racing
  /// the first and hitting the controller's _current getter after the first
  /// already cleared it. Staying here would leave a screen editing a session
  /// that accepts no writes, so refetch and get out.
  void _handleAlreadyClosed(ScaffoldMessengerState messenger) {
    ref.invalidate(activeSessionProvider);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      const SnackBar(content: Text('This session was already finished.')),
    );
  }

  /// A set write the server refused because the session is no longer in
  /// progress. Spec section 8: the logger closes and the Plan tab refetches,
  /// rather than leaving a screen editing a session that accepts no writes.
  ///
  /// [SetRow]'s own blanket catch would otherwise turn the 409 into an inline
  /// Retry that can never succeed -- a session closed on another device would
  /// leave the user tapping it forever. Nothing is rethrown once this handles
  /// it: SetRow clears its busy flag as the route pops.
  bool _handledSetWriteClosure(
    ApiException error,
    ScaffoldMessengerState messenger,
  ) {
    if (error.code != 'SESSION_NOT_IN_PROGRESS') return false;
    if (mounted) _handleAlreadyClosed(messenger);
    return true;
  }

  /// The next set to be done: the lowest set number with nothing stored
  /// against it, or null once the exercise is finished.
  int? _activeSetNumber(PlanExercise exercise, ActiveSession session) {
    for (var number = 1; number <= exercise.targetSets; number++) {
      if (session.setFor(exercise.exerciseId, number) == null) return number;
    }
    return null;
  }

  /// Opens the jump sheet and moves to whatever it returns.
  ///
  /// [current] is the clamped index, so the row highlighted as current is
  /// always one that exists.
  /// Saves the unit chosen on the set table's header.
  ///
  /// A preference, not a session mode: nobody wants to re-pick this every
  /// workout, so it goes to the account. A failed write leaves the display on
  /// the old unit, which is honest -- the toggle reflects stored state rather
  /// than optimistically flipping and silently reverting.
  Future<void> _setUnit(WeightUnit unit) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(profileProvider.notifier).patch({'weightUnit': unit.api});
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
      }
    }
  }

  Future<void> _jumpTo(
    List<PlanExercise> exercises,
    ActiveSession? session,
    int current,
  ) async {
    final chosen = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: context.fs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => ExerciseJumpSheet(
        exercises: exercises,
        session: session,
        currentIndex: current,
      ),
    );
    if (chosen != null && mounted) setState(() => _index = chosen);
  }

  Future<void> _finish() async {
    if (_finishing) return;
    final session = ref.read(activeSessionProvider).value;
    if (session == null) return;

    setState(() => _finishing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final done = await ref
          .read(activeSessionProvider.notifier)
          .complete(_elapsedMinutes(session.startedAt));
      if (!mounted) return;
      await _showSummary(done);
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.code == 'SESSION_NOT_IN_PROGRESS') {
        // Closed somewhere else -- another device, or an earlier tap whose
        // response was lost. Staying here would leave a screen editing a
        // session that accepts no writes, so refetch and get out.
        _handleAlreadyClosed(messenger);
        return;
      }
      // Anything else: the session stays in progress and remains resumable,
      // so nothing is lost -- the worst case is finishing it on next launch.
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    } on StateError {
      // The controller's _current contract: state was already null by the
      // time this call reached it (e.g. a first Finish tap already resolved,
      // or an in-flight completion beat this one to the punch). Same
      // resolution as the 409 above -- never let the raw error through.
      if (!mounted) return;
      _handleAlreadyClosed(messenger);
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
      }
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  Future<void> _showSummary(ActiveSession done) async {
    final unit = ref.read(weightUnitProvider);
    // The dialog resolves to whether the button that closed it is already
    // handling the screen's own pop. Done (and a barrier dismiss, which
    // resolves null the same as false) is not, so this closes the screen
    // itself below -- unchanged from before this dialog could lead anywhere
    // else. _addToPlan resolves it true because, once an existing custom plan
    // means it must show the add-to-plan sheet first, this dialog's own
    // "popped" future -- decoupled from whatever _addToPlan does next --
    // would otherwise race that sheet: it resolves as soon as the dialog
    // closes, which lands while the sheet is now the topmost route, so an
    // unconditional pop here would dismiss the sheet instead of the screen.
    // Read once, before the dialog is built: the label describes which act
    // the button performs, and the dialog's builder does not rebuild when the
    // provider changes under it.
    final active = ref.read(activePlanProvider).value;
    final addToPlanWillClose = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('logger.summary'),
        title: const Text('Session complete'),
        content: Text(
          '${done.durationMin} min · ${done.completedSetCount} sets · '
          // Whole numbers: a session's total volume runs to hundreds, where
          // formatWeight's decimal place would be noise rather than precision.
          '${convertFromKg(done.totalVolumeKg ?? 0, unit).toStringAsFixed(0)} '
          '${unit.api} lifted',
        ),
        actions: [
          // Only a hand-picked workout. A plan-backed one is already part of a
          // plan, and offering to add it again would be offering nothing.
          //
          // Offered, never automatic: this workout may have been improvisation,
          // and silently rewriting the plan the user follows is the kind of
          // surprise that costs trust in the whole feature.
          if (done.planId == null)
            TextButton(
              key: const Key('summary.toPlan'),
              onPressed: () => _addToPlan(dialogContext, done),
              // Two acts, two labels -- see the design, section 4. "Add to my
              // plan" over a plan the user has not built is a promise the
              // action does not keep: there is nothing to add to, so the
              // workout becomes the plan and whatever was active goes.
              child: Text(active != null && active.isCustom
                  ? 'Add to my plan'
                  : 'Make this my plan'),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Done'),
          ),
        ],
      ),
    ) ??
        false;
    if (!addToPlanWillClose && mounted) Navigator.of(context).pop();
  }

  /// Sends the finished workout to the user's own plan.
  ///
  /// [dialogContext] is popped first, with `true` -- see [_showSummary] --
  /// so the summary does not sit over a snack bar the user cannot read, and
  /// so that dialog's own pop does not race the add-to-plan sheet below.
  /// This method closes the screen itself once there is nothing left for the
  /// user to interact with: immediately when there is no day to choose, or
  /// once the sheet (or the replace-my-plan question) resolves when there is.
  /// That pop, and the rest of this method, still has to survive a disposed
  /// State: `showAddToPlanSheet` keeps the screen alive for as long as it is
  /// open, but the write it leads to does not wait for it, and neither did
  /// the version of this method before the sheet existed. The messenger and
  /// the container are both captured before any await, but for different
  /// reasons: `planFromSession` can easily still be in flight after the
  /// screen (and this State with it) is gone, and `ref.invalidate` would
  /// throw against a disposed State -- the container outlives the widget, so
  /// the refresh does too. Neither outcome's message is gated on `mounted`
  /// for the same reason the messenger is captured at all: by the time one
  /// lands there is usually no screen left, and the host scaffold below is
  /// what shows it. Same pattern as `generator_screen.dart`'s `_generate`
  /// and `exercise_swap_sheet.dart`'s `_choose`, for the same reason.
  Future<void> _addToPlan(BuildContext dialogContext, ActiveSession done) async {
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    Navigator.of(dialogContext).pop(true);

    final active = ref.read(activePlanProvider).value;
    // Only an existing custom plan has days to choose between. A first
    // workout, or one landing on top of a generated plan, creates the plan --
    // there is nothing to place it among yet.
    int? dayNo;
    var cancelled = false;
    if (active != null && active.isCustom) {
      if (!mounted) return;
      final choice = await showAddToPlanSheet(context, active);
      cancelled = choice.cancelled;
      dayNo = choice.dayNo;
    } else if (active != null) {
      // A generated plan is about to be deactivated and replaced by a
      // one-day plan built from this workout, and plan history is out of
      // scope -- nothing brings it back. The generator already asks before
      // replacing a plan the user built; this is the same question in the
      // direction that used to be silent.
      if (!mounted) return;
      cancelled = !await _confirmReplacing(active);
    }
    // Either way the session is finished, so the logger leaves: _showSummary
    // handed its own pop to this method the moment the offer was tapped, and
    // backing out of the question must not strand the user on a logger whose
    // session is already closed.
    if (mounted) Navigator.of(context).pop();
    if (cancelled) return;

    try {
      final plan = await ref.read(planRepositoryProvider).planFromSession(
            sessionId: done.sessionId,
            splitStyle: ref.read(chosenSplitStyleProvider),
            dayNo: dayNo,
          );
      // The Plan tab and Home both read this, and neither was watching while
      // the logger was open. Through the container, not ref -- see above.
      container.invalidate(activePlanProvider);
      // Not gated on `mounted`: this State is normally already disposed by
      // now -- the route pops on tap, while the request is still in flight --
      // and the captured messenger belongs to the host scaffold the pop
      // returned to, which is very much alive. Gating it here would mean
      // nothing at all appeared on any connection slower than the pop
      // animation, for either outcome. Same as generator_screen.dart.
      messenger.showSnackBar(
        SnackBar(content: Text('Added to ${plan.name}.')),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    }
  }

  /// Asks before a plan the user did not build is replaced by one made from
  /// this workout. Names the plan, because "your plan" is not enough to
  /// decide by.
  Future<bool> _confirmReplacing(WorkoutPlan plan) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          key: const Key('summary.replacePlan'),
          title: const Text('Replace your current plan?'),
          content: Text(
            'This workout becomes a plan of your own, and "${plan.name}" '
            'goes. You cannot get it back.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep it'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Replace it'),
            ),
          ],
        ),
        // A barrier dismiss is not an answer, and the destructive reading of
        // silence is the wrong one here.
      ) ??
      false;

  Future<void> _discard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard this session?'),
        content: const Text('Sets you have already logged will not be kept.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep going'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(activeSessionProvider.notifier).abandon();
      if (mounted) Navigator.of(context).pop();
    } on StateError {
      // Same _current contract as _finish: already closed elsewhere by the
      // time this reached the controller. Same resolution as the 409 path.
      if (!mounted) return;
      _handleAlreadyClosed(messenger);
    } catch (error) {
      // The abandon did not land, so the session is untouched and still in
      // progress -- nothing was thrown away and it stays resumable. Say so
      // rather than letting a destructive tap look like it did nothing.
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
      }
    }
  }

  /// The logger's chrome, shared by the loaded state and the empty-day
  /// one below. Both need the same way out: back steps through the
  /// workout, and the overflow still carries Finish and Discard. The
  /// empty state needs them most -- POST /sessions has already created
  /// the session row by the time this screen can see the day is empty,
  /// so a screen without them would strand a real session.
  ///
  /// [doneSets] only keys the rest countdown, which restarts on each
  /// new set; the empty state never rests, so it passes zero.
  PreferredSizeWidget _appBar(FsTokens t, {int doneSets = 0}) => AppBar(
      // The mockup's 38px rounded-square icon button, not Material's bare
      // arrow. Tooltipped 'Back' so the platform affordance -- and
      // tester.pageBack -- still finds it, and maybePop routes it through
      // the PopScope above, which is what steps an exercise back.
      leadingWidth: 58,
      leading: Padding(
        padding: const EdgeInsets.only(left: 20),
        child: Tooltip(
          message: 'Back',
          child: InkWell(
            key: const Key('logger.back'),
            onTap: () => Navigator.maybePop(context),
            borderRadius: BorderRadius.circular(FsRadius.sm),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(FsRadius.sm),
                border: Border.all(color: t.line),
              ),
              child: Icon(Icons.chevron_left, size: 19, color: t.text),
            ),
          ),
        ),
      ),
      titleSpacing: 10,
      title: Text(
        'Logging',
        style: TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.74,
          color: t.text,
        ),
      ),
      actions: [
        // The rest countdown is a tag up here rather than a card over the
        // content, so ticking a set does not shove the set table down.
        // Logging stage only: the demo has no sets on it, so a countdown
        // between sets has nothing to count between there.
        if (_resting && _stage == _LoggerStage.logging) ...[
          RestTimer(
            // A fresh key restarts the countdown on each new set.
            key: ValueKey('rest-$doneSets'),
            duration: _restDuration,
            onDone: () => setState(() => _resting = false),
            onSkip: () => setState(() => _resting = false),
          ),
          const SizedBox(width: 6),
        ],
        // Finish lives here as well as on the footer button, so stopping a
        // workout early does not mean paging to the end of it first.
        PopupMenuButton<String>(
          key: const Key('logger.menu'),
          onSelected: (value) => value == 'finish' ? _finish() : _discard(),
          itemBuilder: (_) => const [
            PopupMenuItem(
              key: Key('logger.finish'),
              value: 'finish',
              child: Text('Finish session'),
            ),
            PopupMenuItem(
              key: Key('logger.discard'),
              value: 'discard',
              child: Text('Discard session'),
            ),
          ],
        ),
        const SizedBox(width: 8),
      ],
  );

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final asyncPlan = ref.watch(activePlanProvider);
    final plan = asyncPlan.value;
    final live = ref.watch(activeSessionProvider).value;
    final unit = ref.watch(weightUnitProvider);
    if (live != null) _lastSeenSession = live;
    final session = live ?? _lastSeenSession;

    if (session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // A session started from a chosen list carries its own exercises and has
    // neither a plan nor a rotation day. Requiring a plan here is what left
    // such a session on a bare spinner -- no AppBar, no way back -- after
    // POST /sessions had already opened it.
    final carried = session.exercises;

    // Only a session that needs the plan waits for it. Falling through while
    // it is still in flight would flash the empty state at a plan-backed
    // session whose exercises are one frame away.
    if (carried.isEmpty && asyncPlan.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // The session's own list wins: a manual session must not fall through to
    // whatever plan the user happens to have and log against someone else's
    // day.
    final exercises = carried.isNotEmpty
        ? carried
        : (plan?.exercisesForDay(session.planDayNo) ?? const <PlanExercise>[]);
    if (exercises.isEmpty) {
      // Not a spinner: the plan and the session are both loaded, so there is
      // nothing left to wait for -- this day of the rotation simply holds no
      // exercises. A spinner here promised a list that was never coming, on a
      // bare Scaffold with no AppBar and no way back, after POST /sessions
      // had already opened the session. The ML service refuses to generate
      // such a plan now, so this is the older-plan and edited-rows case
      // rather than the everyday one, but it is still a session someone has
      // to be able to leave or discard.
      return Scaffold(
        backgroundColor: t.bg,
        appBar: _appBar(t),
        body: Center(
          key: const Key('logger.emptyDay'),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FsIconTile(icon: Icons.fitness_center, size: 56),
                const SizedBox(height: 16),
                Text('Nothing to train here',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  'This day of your plan has no exercises. Go back, or '
                  'discard the session from the menu above.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: t.text2),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final index = _index.clamp(0, exercises.length - 1);
    _syncDrafts(index);
    // After the swap above, never before it. An exercise change and a unit
    // confirmation can land in the same frame -- the jump sheet is one tap
    // away from the header's toggle -- and converting first would rewrite the
    // text in the store _syncDrafts is about to throw away, leaving the store
    // actually on screen holding kg under an lb heading.
    //
    // Convert against the CONFIRMED unit only -- see [_unitOnScreen]. This is
    // what SetRow.didUpdateWidget used to do before the refactor, firing only
    // when the (confirmed) unit prop actually changed.
    if (_unitOnScreen != null && _unitOnScreen != unit) {
      _drafts.convert(_unitOnScreen!, unit);
    }
    _unitOnScreen = unit;
    final exercise = exercises[index];
    final isLast = index == exercises.length - 1;

    final targetSets =
        exercises.fold<int>(0, (total, exercise) => total + exercise.targetSets);
    final doneSets = session.completedSetCount;

    final last = ref
        .watch(lastPerformanceProvider(
          lastPerformanceKey(exercises.map((e) => e.exerciseId)),
        ))
        .value;

    // Back steps through the workout before it leaves it. PopScope
    // rather than an AppBar leading override, because the Android system
    // back gesture arrives the same way -- two routes back that disagreed
    // about what "back" means would be worse than either alone. At the
    // first exercise it pops for real, leaving the session in progress and
    // resumable, exactly as it did before paging.
    return PopScope(
      canPop: index == 0 && _stage == _LoggerStage.demo,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        setState(() {
          if (_stage == _LoggerStage.logging) {
            _stage = _LoggerStage.demo;
          } else {
            // Stepping back lands on the previous exercise's table, not on a
            // demo that has already been read.
            _index = index - 1;
            _stage = _LoggerStage.logging;
          }
        });
      },
      child: Scaffold(
        backgroundColor: t.bg,
        appBar: _appBar(t, doneSets: doneSets),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: InkWell(
                          key: const Key('logger.position'),
                          onTap: () => _jumpTo(exercises, session, index),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  'Exercise ${index + 1} / ${exercises.length}'
                                  // A session started from a chosen list has
                                  // no plan to name, and trailing off after
                                  // the separator reads as a rendering fault.
                                  ' · ${plan?.name ?? 'Manual workout'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 11, color: t.text3),
                                ),
                              ),
                              Icon(
                                Icons.arrow_drop_down,
                                size: 16,
                                color: t.text3,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${_elapsedMinutes(session.startedAt)} min elapsed',
                        style: TextStyle(
                          fontFamily: fsMonoFamily,
                          fontSize: 11,
                          color: t.text3,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // The mockup carries no set count in the meta row -- the bar
                  // is the whole story there. Kept as a semantic label, since
                  // a bar is the one thing a screen reader cannot read.
                  Semantics(
                    key: const Key('logger.progress'),
                    label: '$doneSets of $targetSets sets',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: targetSets == 0 ? 0 : doneSets / targetSets,
                        minHeight: 8,
                        backgroundColor: t.surface2,
                        valueColor: AlwaysStoppedAnimation<Color>(t.accent),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _stage == _LoggerStage.demo
                  ? ExerciseDemoStage(
                      key: const Key('logger.demo'),
                      exercise: exercise,
                      position: index + 1,
                      total: exercises.length,
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: ExerciseLogPanel(
                        exercise: exercise,
                        session: session,
                        last: last?[exercise.exerciseId],
                        drafts: _drafts,
                        unit: unit,
                        onUnitChanged: _setUnit,
                        baseUrl: ref.watch(exerciseRepositoryProvider).baseUrl,
                        onUndoSet: (setNumber) async {
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            await ref
                                .read(activeSessionProvider.notifier)
                                .unlogSet(
                                  exerciseId: exercise.exerciseId,
                                  setNumber: setNumber,
                                );
                          } on ApiException catch (error) {
                            if (!_handledSetWriteClosure(error, messenger)) {
                              rethrow;
                            }
                            return;
                          }
                          // The stored set is gone; let the table re-seed
                          // this row from it on the next build.
                          _drafts.release(setNumber);
                        },
                        onOpenDemo: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => InSessionExerciseScreen(
                              exercise: exercise,
                              position: index + 1,
                              total: exercises.length,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: _stage == _LoggerStage.demo
                    ? FsButton(
                        // The same key as the logging stage's footer: one
                        // primary action, in one place, whichever face of the
                        // exercise is showing.
                        key: const Key('logger.primary'),
                        label: 'Start logging',
                        icon: const Icon(Icons.arrow_forward),
                        onPressed: () =>
                            setState(() => _stage = _LoggerStage.logging),
                      )
                    : LoggerAction(
                        activeSetNumber: _activeSetNumber(exercise, session),
                        isLastExercise: isLast,
                        drafts: _drafts,
                        unit: unit,
                        finishing: _finishing,
                        onCompleteSet: (setNumber, weightKg, reps) async {
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            await ref
                                .read(activeSessionProvider.notifier)
                                .logSet(
                                  exerciseId: exercise.exerciseId,
                                  setNumber: setNumber,
                                  weightKg: weightKg,
                                  reps: reps,
                                );
                          } on ApiException catch (error) {
                            if (!_handledSetWriteClosure(error, messenger)) {
                              rethrow;
                            }
                            return;
                          }
                          if (mounted) setState(() => _resting = true);
                        },
                        onNextExercise: () => setState(() {
                          _index = index + 1;
                          // The next exercise opens on its demo, the same
                          // as the first one did.
                          _stage = _LoggerStage.demo;
                        }),
                        onFinish: _finish,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
