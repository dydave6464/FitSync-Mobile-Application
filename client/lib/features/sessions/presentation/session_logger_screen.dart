import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/theme.dart';
import '../../../core/units.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../exercises/presentation/providers.dart'
    show exerciseDetailProvider, exerciseRepositoryProvider;
import '../../exercises/presentation/exercise_list_screen.dart'
    show describeError;
import '../../plans/domain/workout_plan.dart';
import '../../plans/presentation/add_to_plan_sheet.dart';
import '../../plans/presentation/exercise_swap_sheet.dart';
import '../../plans/presentation/make_plan_sheet.dart';
import '../../plans/presentation/providers.dart';
import '../../profile/presentation/providers.dart';
import '../data/rest_alerts.dart';
import '../domain/active_session.dart';
import '../domain/encouragement.dart';
import '../domain/rest_period.dart';
import 'in_session_exercise_screen.dart';
import 'open_workout_summary.dart';
import 'providers.dart';
import 'widgets/encouragement_card.dart';
import 'widgets/exercise_demo_stage.dart';
import 'widgets/exercise_jump_sheet.dart';
import 'widgets/exercise_log_panel.dart';
import 'widgets/logger_action.dart';
import 'widgets/rest_sheet.dart';
import 'widgets/rest_timer.dart';
import 'widgets/set_drafts.dart';

/// The active workout, one exercise at a time: its set table, Continue to
/// the next, and the jump sheet for anything out of order.
class SessionLoggerScreen extends ConsumerStatefulWidget {
  const SessionLoggerScreen({super.key, this.resume = false});

  /// Opens on where the workout was left -- the first exercise with a set
  /// still to do -- instead of exercise 1's demo. For the ways back into a
  /// session already under way: Home's card, the Plan tab's Resume, and the
  /// review screen's question about a workout already open.
  final bool resume;

  @override
  ConsumerState<SessionLoggerScreen> createState() =>
      _SessionLoggerScreenState();
}

/// Which face of the current exercise is on screen. Two faces of one
/// exercise, which is why this is a field and not a second route: the
/// session, the rest countdown and the draft store all live in the State
/// below, and a pushed route would have to be handed every one of them.
enum _LoggerStage { demo, logging }

/// The position counter, spelled in one place.
///
/// It is on screen twice at once whenever the demo is the stage showing --
/// once in the meta row with the plan's name after it, once as the stage's
/// own eyebrow -- and two spellings of one number read as two numbers. So
/// neither call site writes it out.
String _positionLabel(int index, int count) => 'Exercise ${index + 1} / $count';

/// Whether the exercise on screen can be switched, for the app bar's menu and
/// the demo stage's link. [onSwitch] is null while it cannot: the menu greys
/// its item and the link is not shown.
class _SwitchState {
  const _SwitchState(this.onSwitch);

  final VoidCallback? onSwitch;
}

class _SessionLoggerScreenState extends ConsumerState<SessionLoggerScreen>
    with WidgetsBindingObserver {
  /// Which exercise is on screen.
  ///
  /// Read through a clamp rather than corrected on write: the active plan can
  /// change under a resumed session, and an index left past the end of a
  /// shortened plan would throw on the next build.
  int _index = 0;

  /// Which face of [_index]'s exercise is showing. Demo first: this
  /// initialiser is what opens the workout on the first exercise's demo,
  /// unless a resume places it -- and every later move sets it explicitly at
  /// the point the move is made.
  _LoggerStage _stage = _LoggerStage.demo;

  /// Whether the first build with the exercise list still has to put the
  /// screen where the workout was left -- see [SessionLoggerScreen.resume].
  /// Once only: a later rebuild that moved the screen again would drag back
  /// someone who has since moved on their own.
  late bool _resumePending = widget.resume;

  /// The rest between sets, while one is running. Held here rather than in
  /// the app-bar tag, which is rebuilt with the bar: the rest has to outlive
  /// that, and the tag and the sheet both draw it.
  RestPeriod? _rest;

  /// What the tag and an open rest sheet draw; null when no rest is running.
  final _restReading = ValueNotifier<RestReading?>(null);

  /// Repaints the rest once a second. Only a repaint: the time left is always
  /// worked out from the clock, so a tick that is late, or never comes while
  /// the phone is locked, costs nothing.
  Timer? _restTicker;

  /// The few seconds after a rest runs out, when the tag says so in words.
  bool _restOver = false;
  Timer? _restOverTimer;

  /// Whether the logger is on screen, as the app lifecycle reports it. Away,
  /// the rest's end belongs to the phone's notification, not to a buzz
  /// nobody feels.
  bool _appVisible = true;

  /// The alert's text, from the exercise on screen. Set in build rather than
  /// as each rest starts: a rest carries across exercises, and a body fixed
  /// at the set would name an exercise the user has already left.
  String _restAlertBody = 'Time for your next exercise.';

  /// Read once, in initState: dispose cancels through it, and a first
  /// `ref.read` during dispose is not allowed.
  late final RestAlertScheduler _alerts;

  @override
  void initState() {
    super.initState();
    _alerts = ref.read(restAlertSchedulerProvider);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        // Hidden and then paused: one alert, scheduled on the first.
        if (!_appVisible) return;
        _appVisible = false;
        unawaited(_scheduleRestAlert());
      case AppLifecycleState.resumed:
        _appVisible = true;
        unawaited(_alerts.cancel());
        // A rest that ran out while away ends now: shown, not buzzed -- the
        // notification already said so.
        final rest = _rest;
        if (rest != null && rest.isOverAt(_now()) && mounted) {
          setState(() => _endRest(ranOut: true));
        } else if (rest != null) {
          _publishRest();
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// One notification for the moment the rest ends, while the phone is away.
  /// Re-checked after every wait: coming back can land in between, and an
  /// alert scheduled after that would fire at someone looking at the screen.
  Future<void> _scheduleRestAlert() async {
    final rest = _rest;
    if (rest == null || rest.isOverAt(_now())) return;
    final enabled = await ref.read(restAlertEnabledProvider.future);
    if (!mounted || !enabled || _appVisible || _rest != rest) return;
    if (!await _alerts.permissionGranted()) return;
    if (!mounted || _appVisible || _rest != rest) return;
    await _alerts.schedule(
      at: rest.endsAt,
      title: 'Rest over',
      body: _restAlertBody,
    );
    // Not `_rest != rest`: a newer rest has scheduled its own alert by now,
    // under the same id, and cancelling would take that one away too.
    if (!mounted || _appVisible || _rest == null) await _alerts.cancel();
  }

  /// The first rest is when an alert first makes sense, so it is where the
  /// phone's permission prompt appears -- once per phone. On an iPhone a "no"
  /// is final, and asking again on every rest would only nag; the sheet's
  /// switch points to the phone's settings instead.
  Future<void> _askRestAlertPermissionOnce() async {
    final store = ref.read(restAlertStoreProvider);
    final enabled = await ref.read(restAlertEnabledProvider.future);
    if (!enabled || await _alerts.permissionGranted()) return;
    if (await store.asked()) return;
    await store.markAsked();
    await _alerts.requestPermission();
  }

  DateTime _now() => ref.read(restNowProvider)();

  void _startRest(int seconds) {
    _restOverTimer?.cancel();
    _restOver = false;
    _rest = RestPeriod.start(_now(), seconds);
    // A fresh ticker rather than the running one, so a rest started mid-rest
    // ticks in step with its own start: the old one's phase would show the
    // first number late and notice the end up to a second after it.
    _restTicker?.cancel();
    _restTicker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _onRestTick(),
    );
    _publishRest();
  }

  void _onRestTick() {
    final rest = _rest;
    if (rest == null || !mounted) return;
    // Away, nothing to repaint and nobody to buzz: a rest that runs out in
    // the meantime is ended on the way back (didChangeAppLifecycleState).
    if (!_appVisible) return;
    if (rest.isOverAt(_now())) {
      setState(() => _endRest(ranOut: true));
      _signalRestOver();
    } else {
      _publishRest();
    }
  }

  void _publishRest() {
    final rest = _rest!;
    final now = _now();
    _restReading.value = (
      secondsLeft: rest.secondsLeft(now),
      fractionLeft: rest.fractionLeft(now),
    );
  }

  /// ±seconds from the sheet: this rest only, never the saved default.
  /// Cutting it to nothing ends it.
  void _adjustRest(int seconds) {
    final rest = _rest;
    if (rest == null) return;
    final next = rest.adjusted(seconds, _now(), maxSeconds: restMaxSeconds);
    if (next == null) {
      _endRest();
      return;
    }
    _rest = next;
    _publishRest();
  }

  /// Stops the rest, if one is running. Callers wrap it in setState: the tag
  /// changes with it. Only a rest that [ranOut] says "Rest over" -- Skip,
  /// −30s to nothing and the like were the user's own doing, and need no
  /// telling.
  void _endRest({bool ranOut = false}) {
    _restTicker?.cancel();
    _restTicker = null;
    if (_rest == null) return;
    _rest = null;
    _restReading.value = null;
    // However it ended, an alert scheduled for its end is now wrong: Finish
    // can land after the phone has locked and one was scheduled.
    unawaited(_alerts.cancel());
    if (!ranOut) return;
    _restOver = true;
    _restOverTimer?.cancel();
    _restOverTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _restOver = false);
    });
  }

  /// One buzz and one announcement, never repeated: the tag says "Rest over"
  /// for whoever is looking, this is for whoever is not.
  void _signalRestOver() {
    HapticFeedback.vibrate();
    SemanticsService.sendAnnouncement(
      View.of(context),
      'Rest over',
      TextDirection.ltr,
    );
  }

  /// One store per exercise on screen. Rebuilt when the exercise changes, so
  /// a set number means one thing at a time.
  SetDrafts _drafts = SetDrafts();

  /// The position and exercise [_drafts] was made for. Both, because a switch
  /// changes the exercise and leaves the position alone.
  (int, int)? _draftsFor;

  /// The unit last confirmed on screen -- i.e. actually read back from
  /// [weightUnitProvider], not merely requested. Null until the first build
  /// that gets as far as the exercise list, which the demo stage counts as
  /// much as the set table does -- this is assigned before the stage is
  /// chosen. So the very first frame never "converts" against nothing, and a
  /// unit confirmed while the screen is still loading (or sitting on an empty
  /// day) converts once there is a store to convert.
  ///
  /// Converting against this rather than in `_setUnit` itself means a
  /// failed profile write leaves the typed text alone: the display stays on
  /// the old unit, and so does whatever was typed under it, until the write
  /// actually lands and this unit changes for real.
  WeightUnit? _unitOnScreen;

  /// Swaps the store when the exercise changes. Called from build, which is
  /// the only place that knows the clamped index and the exercise at it.
  ///
  /// Keyed on the exercise as well as the index: a switch keeps the index,
  /// and its new plan can land with no word from the sheet -- dismissed while
  /// the swap was still in flight -- or after a slow refetch the user has
  /// already started typing into. Either way the numbers on screen were meant
  /// for the exercise just replaced, and a prefill only fills blank fields,
  /// so they would otherwise stay.
  ///
  /// One job, deliberately. Resetting [_stage] from here as well would tie the
  /// stage to the store's lifetime, and the back handler would then need the
  /// early return below to keep the table it is stepping back to -- which
  /// skips the swap too, and hands the previous exercise the kg and reps typed
  /// against this one. Stage is an outcome of navigation, so every move sets
  /// it where the move is made.
  void _syncDrafts(int index, int exerciseId) {
    final key = (index, exerciseId);
    if (key == _draftsFor) return;
    _drafts.dispose();
    _drafts = SetDrafts();
    _draftsFor = key;
  }

  @override
  void dispose() {
    _drafts.dispose();
    _restTicker?.cancel();
    _restOverTimer?.cancel();
    _restReading.dispose();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_alerts.cancel());
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

  /// The exercises the last build drew. Finish is reached from the menu and
  /// the footer, neither of which carries the list, and its question counts
  /// and names what is left in it.
  List<PlanExercise> _exercisesOnScreen = const [];

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
    // As in _discard: the rest's alert goes now, not when the pop finishes.
    setState(_endRest);
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
  /// [LoggerAction]'s own blanket catch would otherwise turn the 409 into a
  /// Retry that can never succeed -- a session closed on another device would
  /// leave the user tapping it forever. Nothing is rethrown once this handles
  /// it: the footer button clears its busy flag as the route pops.
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

  /// Every move this screen makes: which exercise, and which face of it.
  /// Call it inside a setState. Seven paths lead here -- Start logging, Next
  /// exercise, both halves of back, the jump sheet, a switch, and a resume,
  /// which is the one that runs inside build rather than a setState.
  ///
  /// Moving never touches the rest: a rest is the user's, between their sets,
  /// whichever exercise is on screen -- the walk from one station to the next
  /// is part of it.
  ///
  /// One route does NOT come through here, and is left alone deliberately:
  /// the index clamp in build() reads [_index] against a plan that may have
  /// shrunk under a resumed session, so the exercise on screen can change
  /// without a move having been made -- [_stage] is not reset. It needs the
  /// active plan to lose exercises while a session against it is open, and
  /// the result is no worse than it was before this branch, so it is written
  /// down rather than fixed.
  void _moveTo({int? index, required _LoggerStage stage}) {
    if (index != null) _index = index;
    _stage = stage;
  }

  /// Whether anything at all has been logged against [exercise] in this
  /// session. Not the inverse of [_activeSetNumber]: undoing a set leaves a
  /// hole, so an exercise can have set 1 open and set 2 stored, and "the next
  /// set to do is 1" would then read as untouched when it is not.
  bool _hasLoggedSets(PlanExercise exercise, ActiveSession? session) {
    if (session == null) return false;
    for (var number = 1; number <= exercise.targetSets; number++) {
      if (session.setFor(exercise.exerciseId, number) != null) return true;
    }
    return false;
  }

  /// Where the workout was left: the first exercise with a set still to do,
  /// on its table if anything is logged on it and on its demo if not -- the
  /// same rule as a jump. With every set done, the last exercise's table,
  /// where Finish is.
  (int, _LoggerStage) _whereLeftOff(
    List<PlanExercise> exercises,
    ActiveSession session,
  ) {
    for (var i = 0; i < exercises.length; i++) {
      if (_activeSetNumber(exercises[i], session) == null) continue;
      return (
        i,
        _hasLoggedSets(exercises[i], session)
            ? _LoggerStage.logging
            : _LoggerStage.demo,
      );
    }
    return (exercises.length - 1, _LoggerStage.logging);
  }

  /// Replaces [exercise] in the plan, from inside the workout: the same sheet
  /// and the same server swap the Plan tab's Change button uses, so the plan
  /// row itself changes, for every later session too.
  ///
  /// The sheet refreshes the active plan, which this screen watches, so the
  /// new exercise arrives at the same position on its own; [_index] is left
  /// where it is. Nothing moves until that refreshed plan has landed: until
  /// then the old exercise is still on screen, Switch link and all, and a
  /// "Swapped to" over it would be a claim the screen contradicts. If the
  /// refetch fails, the old plan stays, so the screen stays with it and says
  /// why rather than announcing a switch it cannot show.
  ///
  /// Once it lands, the demo is what shows next -- the user has not read this
  /// one yet. The drafts need nothing here: the new exercise at this position
  /// already gave [_syncDrafts] a new key in the build that drew it. The rest
  /// is not touched; see [_moveTo].
  ///
  /// No Undo on the SnackBar. Every swap is recorded server-side as "rejected
  /// this, chose that" for the recommender, so swapping straight back would
  /// record a rejection the user never meant; Switch again is the way back.
  Future<void> _switchExercise(PlanExercise exercise) async {
    final messenger = ScaffoldMessenger.of(context);
    final swappedTo = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ExerciseSwapSheet(
        planExerciseId: exercise.planExerciseId,
        exerciseName: exercise.name,
        onGoToProfile: null,
      ),
    );
    if (swappedTo == null || !mounted) return;
    try {
      await ref.read(activePlanProvider.future);
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
      return;
    }
    if (!mounted) return;
    setState(() => _moveTo(stage: _LoggerStage.demo));
    messenger.showSnackBar(
      SnackBar(
        // Floating, and lifted past the footer: Start logging is the next
        // tap after a switch, and a SnackBar along the bottom edge would sit
        // on it for as long as it shows.
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(16, 0, 16, _footerHeight() + 8),
        duration: const Duration(seconds: 4),
        content: Text('Swapped to $swappedTo'),
      ),
    );
  }

  /// Takes a stored set back so it can be corrected: the tap on a logged row.
  ///
  /// The row keeps the set's own numbers. Emptying it let the next build fill
  /// the blanks with last session's, so a mis-tap cost the numbers actually
  /// lifted. The seed is authoritative, so it replaces what the row showed,
  /// and a prefill only fills blank fields, so it leaves these alone.
  ///
  /// Undo rather than a question first: reopening is frequent and costs
  /// nothing once Undo can put the set back.
  Future<void> _reopenSet(PlanExercise exercise, int setNumber) async {
    final messenger = ScaffoldMessenger.of(context);
    // Read before the delete, which is what takes it out of the session.
    final stored = ref
        .read(activeSessionProvider)
        .value
        ?.setFor(exercise.exerciseId, setNumber);
    final drafts = _drafts;
    try {
      await ref
          .read(activeSessionProvider.notifier)
          .unlogSet(exerciseId: exercise.exerciseId, setNumber: setNumber);
    } on ApiException catch (error) {
      if (!_handledSetWriteClosure(error, messenger)) rethrow;
      return;
    }
    // A move while the delete was in flight has thrown this store away, and
    // the store now on screen belongs to another exercise.
    if (!mounted || !identical(drafts, _drafts)) return;
    if (stored == null) {
      drafts.release(setNumber);
      return;
    }
    drafts.seed(
      setNumber: setNumber,
      weightKg: stored.weightKg,
      reps: stored.reps,
      unit: _unitOnScreen ?? ref.read(weightUnitProvider),
      authoritative: true,
    );
    messenger.showSnackBar(
      SnackBar(
        // Lifted past the footer, as "Swapped to" is: Complete set is how a
        // corrected set is saved, so it is the next tap.
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(16, 0, 16, _footerHeight() + 8),
        duration: const Duration(seconds: 4),
        // An action makes a SnackBar persist by default, which would keep
        // this one up after its Undo stopped meaning anything, with every
        // later message queued behind it. It times out like "Swapped to",
        // except for a screen reader, which needs time to reach Undo.
        persist: MediaQuery.accessibleNavigationOf(context),
        content: Text('Set $setNumber reopened'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => _undoReopen(stored, messenger),
        ),
      ),
    );
  }

  /// Logs [stored] again exactly as it was. Not a new set, so no rest starts:
  /// only Complete set starts one.
  ///
  /// Nothing happens if the set is already stored again -- corrected and
  /// saved before Undo was tapped. That correction is the user's latest word,
  /// and the old numbers must not overwrite it.
  Future<void> _undoReopen(
    LoggedSet stored,
    ScaffoldMessengerState messenger,
  ) async {
    // The SnackBar outlives the logger: it belongs to the host's messenger.
    if (!mounted) return;
    final session = ref.read(activeSessionProvider).value;
    if (session == null ||
        session.setFor(stored.exerciseId, stored.setNumber) != null) {
      return;
    }
    try {
      await ref
          .read(activeSessionProvider.notifier)
          .logSet(
            exerciseId: stored.exerciseId,
            setNumber: stored.setNumber,
            weightKg: stored.weightKg,
            reps: stored.reps,
          );
    } on ApiException catch (error) {
      if (_handledSetWriteClosure(error, messenger)) return;
      _undoFailed(messenger, error);
    } catch (error) {
      _undoFailed(messenger, error);
    }
  }

  /// The set stays open with its numbers in the row, so Complete set still
  /// saves it; the message says why Undo did not.
  void _undoFailed(ScaffoldMessengerState messenger, Object error) {
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
  }

  /// Marks the footer, so a SnackBar can be lifted clear of it.
  final _footerKey = GlobalKey();

  /// How tall the footer is now, safe area included. Measured rather than
  /// fixed: the button grows with large text.
  double _footerHeight() {
    final box = _footerKey.currentContext?.findRenderObject() as RenderBox?;
    return box != null && box.hasSize ? box.size.height : 0;
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
    final chosen = await showExerciseJumpSheet(
      context,
      exercises: exercises,
      session: session,
      currentIndex: current,
    );
    if (chosen != null && mounted) {
      setState(() {
        // The demo prepares you for a movement you are about to do. An
        // exercise you have already logged sets against is one you were
        // already prepared for, so jumping back to fix a set lands on the
        // table -- matching the back handler -- while jumping forward to
        // something untouched still shows its cues.
        _moveTo(
          index: chosen,
          stage: _hasLoggedSets(exercises[chosen], session)
              ? _LoggerStage.logging
              : _LoggerStage.demo,
        );
      });
    }
  }

  /// Closes the logger and leaves the session in progress, from wherever the
  /// user is. Back steps through the exercises first, so without this,
  /// leaving from the last one took a press per exercise. Nothing is written:
  /// the session is resumable from Train, and opens where it was left. The
  /// rest ends with the screen, in dispose.
  void _leave() {
    // Captured before the pop, as in _handleAlreadyClosed: the message
    // belongs on the screen underneath.
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    // A reopen's Undo is still up for up to four seconds; it would hold this
    // message back, and leaving is the newer news.
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Workout saved. Resume it any time from Train.'),
      ),
    );
  }

  Future<void> _finish() async {
    if (_finishing) return;
    final session = ref.read(activeSessionProvider).value;
    if (session == null) return;
    // Guarded only once the user has said Finish. The footer button locks
    // while _finishing is set, and a question still open, or answered Keep
    // going, is not a finish in flight.
    if (!await _confirmFinish(session) || !mounted || _finishing) return;

    setState(() => _finishing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final done = await ref
          .read(activeSessionProvider.notifier)
          .complete(_elapsedMinutes(session.startedAt));
      if (!mounted) return;
      // The summary sits over this screen; a rest still running under it
      // would buzz at a finished workout.
      setState(_endRest);
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

  /// Asks before a workout with planned sets still unlogged is finished,
  /// since finishing is final. True carries on into the finish; a workout
  /// with nothing left -- or nothing planned -- does not ask.
  ///
  /// Keep going moves to the first exercise with sets left, by the same rule
  /// as a resume. Dismissing the question is not an answer, so nothing
  /// finishes, and not a choice to move either, so nothing moves.
  Future<bool> _confirmFinish(ActiveSession session) async {
    final exercises = _exercisesOnScreen;
    var total = 0;
    var done = 0;
    final left = <String>[];
    for (final exercise in exercises) {
      total += exercise.targetSets;
      final logged = session.sets
          .where((set) => set.exerciseId == exercise.exerciseId)
          .length;
      // Capped at the target: extra sets on one exercise are real work, but
      // they do not make up for another exercise's missing ones.
      done += logged < exercise.targetSets ? logged : exercise.targetSets;
      if (_activeSetNumber(exercise, session) != null) left.add(exercise.name);
    }
    if (done >= total) return true;

    final answer = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('logger.finishConfirm'),
        title: Text('Finish with $done of $total sets?'),
        content: Text('Not logged yet: ${_listNames(left)}.'),
        actions: [
          TextButton(
            key: const Key('logger.finishConfirm.keepGoing'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep going'),
          ),
          TextButton(
            key: const Key('logger.finishConfirm.finish'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Finish'),
          ),
        ],
      ),
    );
    if (answer == false && mounted) {
      setState(() {
        final (index, stage) = _whereLeftOff(exercises, session);
        _moveTo(index: index, stage: stage);
      });
    }
    return answer == true;
  }

  /// "A", "A and B", "A, B and C" -- and past three, "A, B, C and 2 more",
  /// so a long workout's question still fits a small phone.
  static String _listNames(List<String> names) {
    if (names.length > 3) {
      return '${names.take(3).join(', ')} and ${names.length - 3} more';
    }
    if (names.length == 1) return names.single;
    return '${names.sublist(0, names.length - 1).join(', ')} '
        'and ${names.last}';
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
    final addToPlanWillClose =
        await showDialog<bool>(
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
                  child: Text(
                    active != null && active.isCustom
                        ? 'Add to my plan'
                        : 'Make this my plan',
                  ),
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
  /// so that dialog's own pop does not race the sheet below. This method
  /// closes the screen itself once there is nothing left for the user to
  /// interact with: once the sheet it asks on resolves, however it resolves.
  ///
  /// Which sheet depends on the plan already active. A plan of the user's own
  /// has days to choose between, and the workout is added among them. Any
  /// other -- a generated plan, or none -- is replaced by a plan made from
  /// this workout, and [showMakePlanSheet] asks for the split that names it
  /// and, when a plan is about to go, confirms it by name.
  ///
  /// That pop, and the rest of this method, still has to survive a disposed
  /// State: the sheet keeps the screen alive for as long as it is open, but
  /// the write it leads to does not wait for it, and neither did the version
  /// of this method before the sheets existed. The messenger and the
  /// container are both captured before any await, but for different
  /// reasons: `planFromSession` can easily still be in flight after the
  /// screen (and this State with it) is gone, and `ref.invalidate` would
  /// throw against a disposed State -- the container outlives the widget, so
  /// the refresh does too. Neither outcome's message is gated on `mounted`
  /// for the same reason the messenger is captured at all: by the time one
  /// lands there is usually no screen left, and the host scaffold below is
  /// what shows it. Same pattern as `generator_screen.dart`'s `_generate`
  /// and `exercise_swap_sheet.dart`'s `_choose`, for the same reason.
  Future<void> _addToPlan(
    BuildContext dialogContext,
    ActiveSession done,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    Navigator.of(dialogContext).pop(true);

    final active = ref.read(activePlanProvider).value;
    int? dayNo;
    String? splitStyle;
    var cancelled = false;
    if (!mounted) return;
    if (active != null && active.isCustom) {
      final choice = await showAddToPlanSheet(context, active);
      cancelled = choice.cancelled;
      dayNo = choice.dayNo;
    } else {
      splitStyle = await showMakePlanSheet(context, replacing: active);
      cancelled = splitStyle == null;
    }
    // Either way the session is finished, so the logger leaves: _showSummary
    // handed its own pop to this method the moment the offer was tapped, and
    // backing out of the question must not strand the user on a logger whose
    // session is already closed.
    if (mounted) Navigator.of(context).pop();
    if (cancelled) return;

    try {
      final plan = await ref
          .read(planRepositoryProvider)
          .planFromSession(
            sessionId: done.sessionId,
            splitStyle: splitStyle,
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
      messenger.showSnackBar(SnackBar(content: Text('Added to ${plan.name}.')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    }
  }

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
            style: TextButton.styleFrom(foregroundColor: dialogContext.fs.red),
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
      if (!mounted) return;
      // Ended here rather than left to dispose: on a locked phone the pop
      // waits for frames, and the rest's alert would fire for a workout
      // that was thrown away.
      setState(_endRest);
      Navigator.of(context).pop();
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

  /// Clears what has been logged against [exercise] so it can be done again,
  /// leaving the rest of the session alone -- the per-exercise counterpart to
  /// Discard, which throws the whole workout away.
  ///
  /// One delete per stored set, through the same call the set table's reopen
  /// uses, so nothing new is needed server-side. Each delete lands on its own:
  /// if the connection drops partway, the sets already cleared stay cleared
  /// and the message says the restart did not finish, rather than pretending
  /// either everything or nothing happened.
  Future<void> _restartExercise(
    PlanExercise exercise,
    ActiveSession session,
  ) async {
    final logged = [
      for (final set in session.sets)
        if (set.exerciseId == exercise.exerciseId) set.setNumber,
    ];
    if (logged.isEmpty) return;

    final count = logged.length == 1
        ? '1 logged set'
        : '${logged.length} logged sets';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('logger.restartConfirm'),
        title: Text('Restart ${exercise.name}?'),
        content: Text(
          'Your $count for this exercise will be cleared. '
          'The rest of your session is kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: dialogContext.fs.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Restart'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Restarting is a fresh start on this exercise, and the rest goes with
    // the sets it followed: those are being taken back.
    setState(_endRest);
    final messenger = ScaffoldMessenger.of(context);
    final drafts = _drafts;
    for (final setNumber in logged) {
      try {
        await ref
            .read(activeSessionProvider.notifier)
            .unlogSet(exerciseId: exercise.exerciseId, setNumber: setNumber);
      } on ApiException catch (error) {
        if (_handledSetWriteClosure(error, messenger)) return;
        _restartFailed(messenger, exercise, error);
        return;
      } catch (error) {
        _restartFailed(messenger, exercise, error);
        return;
      }
      // Re-seeded from last session on the next build, the way a fresh
      // table is -- see SetDrafts.release.
      drafts.release(setNumber);
    }
  }

  void _restartFailed(
    ScaffoldMessengerState messenger,
    PlanExercise exercise,
    Object error,
  ) {
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          "Couldn't finish restarting ${exercise.name}. ${describeError(error)}",
        ),
      ),
    );
  }

  /// The logger's chrome, shared by the loaded state and the empty-day
  /// one below. Both need the same way out: back steps through the
  /// workout, and the overflow still carries Finish and Discard. The
  /// empty state needs them most -- POST /sessions has already created
  /// the session row by the time this screen can see the day is empty,
  /// so a screen without them would strand a real session.
  ///
  /// [onRestart] is null whenever there is nothing to restart -- the demo
  /// stage, an exercise with no sets logged yet, the empty day -- which
  /// greys the item out rather than hiding it, so the menu keeps one shape.
  ///
  /// [restSeconds] feeds the menu's 'Rest time' label. It is passed in
  /// rather than read here because the screen already watches it for the
  /// rest itself, which takes its length when a set is completed.
  ///
  /// [switchState] is null when the session has no plan to change -- one
  /// started from a chosen list, or the empty day -- and the item is then
  /// absent rather than greyed: there is nothing it could ever do. On a
  /// plan-backed session it stays, greyed with its reason once sets are
  /// logged against the exercise on screen.
  PreferredSizeWidget _appBar(
    FsTokens t, {
    required int restSeconds,
    VoidCallback? onRestart,
    _SwitchState? switchState,
  }) => AppBar(
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
      // On both stages: the rest carries across exercises, so the demo of
      // the next one is exactly where it is still running.
      if (_rest != null || _restOver) ...[
        RestTimer(
          reading: _restReading,
          over: _rest == null && _restOver,
          onOpen: _rest == null
              ? null
              : () => showRestSheet(
                  context,
                  countdown: RestCountdown(
                    reading: _restReading,
                    onAdjust: (seconds) => setState(() => _adjustRest(seconds)),
                    onSkip: () => setState(_endRest),
                  ),
                ),
        ),
        const SizedBox(width: 6),
      ],
      // Finish lives here as well as on the footer button, so stopping a
      // workout early does not mean paging to the end of it first.
      PopupMenuButton<String>(
        key: const Key('logger.menu'),
        onSelected: (value) => switch (value) {
          'restTime' => showRestSheet(context),
          'restart' => onRestart?.call(),
          'switch' => switchState?.onSwitch?.call(),
          'leave' => _leave(),
          'finish' => _finish(),
          _ => _discard(),
        },
        itemBuilder: (_) => [
          // Reachable before the first set, when there is no rest tag yet to
          // tap. Names the current value so the menu answers the question
          // without opening anything.
          PopupMenuItem(
            key: const Key('logger.restTime'),
            value: 'restTime',
            child: Text('Rest time: ${formatRest(restSeconds)}'),
          ),
          PopupMenuItem(
            key: const Key('logger.restart'),
            value: 'restart',
            enabled: onRestart != null,
            child: const Text('Restart this exercise'),
          ),
          if (switchState != null)
            PopupMenuItem(
              key: const Key('logger.switch.menu'),
              value: 'switch',
              enabled: switchState.onSwitch != null,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Switch exercise'),
                  // Greyed with no reason reads as broken. t.text2 rather
                  // than the item's own disabled grey, so the reason stays
                  // readable.
                  if (switchState.onSwitch == null)
                    Text(
                      "You've logged sets on this one",
                      style: TextStyle(fontSize: 12, color: t.text2),
                    ),
                ],
              ),
            ),
          const PopupMenuItem(
            key: Key('logger.leave'),
            value: 'leave',
            child: Text('Leave, keep for later'),
          ),
          const PopupMenuItem(
            key: Key('logger.finish'),
            value: 'finish',
            child: Text('Finish session'),
          ),
          const PopupMenuItem(
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
    final restSeconds =
        ref.watch(restSecondsProvider).value ?? defaultRestSeconds;
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
    //
    // Only the first load, though. A swap refreshes the plan under an open
    // session, and a refresh still holds the plan it is replacing -- falling
    // to the spinner then would blank the whole logger for a frame.
    if (carried.isEmpty && asyncPlan.isLoading && !asyncPlan.hasValue) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // The session's own list wins: a manual session must not fall through to
    // whatever plan the user happens to have and log against someone else's
    // day.
    final exercises = carried.isNotEmpty
        ? carried
        : (plan?.exercisesForDay(session.planDayNo) ?? const <PlanExercise>[]);
    _exercisesOnScreen = exercises;
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
        appBar: _appBar(t, restSeconds: restSeconds),
        body: Center(
          key: const Key('logger.emptyDay'),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FsIconTile(icon: Icons.fitness_center, size: 56),
                const SizedBox(height: 16),
                Text(
                  'Nothing to train here',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
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
    if (_resumePending) {
      _resumePending = false;
      // Assigned here rather than through setState: this build is the one
      // that reads them, a few lines down.
      final (index, stage) = _whereLeftOff(exercises, session);
      _moveTo(index: index, stage: stage);
    }
    final index = _index.clamp(0, exercises.length - 1);
    _syncDrafts(index, exercises[index].exerciseId);
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
    // The rest alert speaks of the exercise on screen, whichever one the rest
    // was started from. A plain assignment, like [_lastSeenSession]: nothing
    // drawn depends on it.
    final next = _activeSetNumber(exercise, session);
    _restAlertBody = next != null
        ? 'Next: set $next of ${exercise.name}'
        : 'Time for your next exercise.';
    final isLast = index == exercises.length - 1;
    // A switch replaces the exercise in the plan, so only a session whose
    // exercises come from the plan has one; and only before anything is
    // logged against it, since those sets would be left naming an exercise
    // the plan no longer holds.
    final switchState = carried.isNotEmpty
        ? null
        : _SwitchState(
            _hasLoggedSets(exercise, session)
                ? null
                : () => _switchExercise(exercise),
          );
    final encouragement = encouragementFor(
      exercises: exercises,
      index: index,
      session: session,
    );

    final targetSets = exercises.fold<int>(
      0,
      (total, exercise) => total + exercise.targetSets,
    );
    final doneSets = session.completedSetCount;

    final last = ref
        .watch(
          lastPerformanceProvider(
            lastPerformanceKey(exercises.map((e) => e.exerciseId)),
          ),
        )
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
            _moveTo(stage: _LoggerStage.demo);
          } else {
            // Stepping back lands on the previous exercise's table, not on a
            // demo that has already been read.
            _moveTo(index: index - 1, stage: _LoggerStage.logging);
          }
        });
      },
      child: Scaffold(
        backgroundColor: t.bg,
        appBar: _appBar(
          t,
          restSeconds: restSeconds,
          onRestart:
              _stage == _LoggerStage.logging &&
                  _hasLoggedSets(exercise, session)
              ? () => _restartExercise(exercise, session)
              : null,
          switchState: switchState,
        ),
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
                                  '${_positionLabel(index, exercises.length)}'
                                  // Named the way Home and History name it.
                                  // Not the active plan's name: a workout
                                  // the user picked themselves is not a day
                                  // of the AI plan they may be replacing.
                                  ' · ${openWorkoutTitle(session, plan)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: t.text3,
                                  ),
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
                      positionLabel: _positionLabel(index, exercises.length),
                      onSwitch: switchState?.onSwitch,
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ExerciseLogPanel(
                            exercise: exercise,
                            session: session,
                            // The same value the footer button names below.
                            activeSetNumber: _activeSetNumber(
                              exercise,
                              session,
                            ),
                            last: last?[exercise.exerciseId],
                            drafts: _drafts,
                            unit: unit,
                            onUnitChanged: _setUnit,
                            baseUrl: ref
                                .watch(exerciseRepositoryProvider)
                                .baseUrl,
                            // The demo stage usually fetched this exercise's
                            // detail on the way in, and the provider keeps it,
                            // so this is normally a cache read and the tile
                            // plays the GIF the stage already loaded. (Not
                            // after a jump straight to a table the demo never
                            // showed this run.) Null until it lands: still tile.
                            animationUrl: ref
                                .watch(
                                  exerciseDetailProvider(exercise.exerciseId),
                                )
                                .value
                                ?.animationUrl,
                            onUndoSet: (setNumber) =>
                                _reopenSet(exercise, setNumber),
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
                          // Directly above the footer that moves on, so the
                          // praise and the next step are read together.
                          if (encouragement != null) ...[
                            const SizedBox(height: 12),
                            EncouragementCard(
                              key: const Key('logger.encouragement'),
                              message: encouragement,
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
            SafeArea(
              key: _footerKey,
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
                        onPressed: () => setState(
                          () => _moveTo(stage: _LoggerStage.logging),
                        ),
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
                          // The length is read here, at the set, so a
                          // default changed in the sheet lands on the next
                          // rest rather than rewinding the one already
                          // counting.
                          if (!mounted) return;
                          setState(() => _startRest(restSeconds));
                          if (_appVisible) {
                            unawaited(_askRestAlertPermissionOnce());
                          } else {
                            // Locked before the server answered: the
                            // lifecycle event that schedules the alert has
                            // already gone by, so this rest schedules its
                            // own. Same id, so it replaces one set for an
                            // earlier rest. No prompt: one shown from the
                            // background would spend the single ask unseen.
                            unawaited(_scheduleRestAlert());
                          }
                        },
                        // The next exercise opens on its demo, the same as
                        // the first one did.
                        onNextExercise: () => setState(
                          () => _moveTo(
                            index: index + 1,
                            stage: _LoggerStage.demo,
                          ),
                        ),
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
