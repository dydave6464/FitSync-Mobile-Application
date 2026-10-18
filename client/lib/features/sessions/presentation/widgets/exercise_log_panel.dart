import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show BoxHitTestEntry, BoxHitTestResult, RenderFittedBox;

import '../../../../core/theme.dart';
import '../../../../core/units.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../../exercises/presentation/exercise_thumb.dart';
import '../../../exercises/presentation/widgets/coaching_tag.dart';
import '../../../plans/domain/workout_plan.dart';
import '../../domain/active_session.dart';
import 'set_drafts.dart';
import 'set_row.dart';

/// The most rows one exercise's set table grows to with "+ Add set".
///
/// The server takes set numbers up to 99, but twenty sets of one exercise is
/// already past any session anyone logs by hand; past it the control would
/// only ever be a mis-tap.
const maxSetsPerExercise = 20;

/// The exercise on screen in the paged logger: its prescription, what was
/// lifted last time, and its set table.
///
/// Always open. The collapsed state this widget used to carry belonged to the
/// scrolling list it lived in; the logger shows one exercise at a time now,
/// and ExerciseJumpSheet is what reaches the others.
///
/// Stateful for one reason: whether an exercise that carries no external load
/// is being done with one today. See [_ExerciseLogPanelState._weightAdded].
class ExerciseLogPanel extends StatefulWidget {
  const ExerciseLogPanel({
    super.key,
    required this.exercise,
    required this.session,
    required this.onUndoSet,
    required this.drafts,
    this.activeSetNumber,
    this.last,
    this.onOpenDemo,
    this.unit = WeightUnit.kg,
    this.onUnitChanged,
    this.baseUrl = '',
    this.animationUrl,
    this.setCount,
    this.onAddSet,
    this.onRemoveSet,
  });

  final PlanExercise exercise;

  /// How many rows the set table has: the target, plus any the user added,
  /// or as many as were logged if that is more. Worked out by the logger,
  /// which also counts these rows for the footer and the finish question.
  /// Null is the target alone.
  final int? setCount;

  /// Adds a row below the last. Null leaves the table at [setCount] rows
  /// with no control to grow it, which is how a panel built without a
  /// logger behind it is drawn.
  final VoidCallback? onAddSet;

  /// Removes the last row, which must be one added past the target and not
  /// yet logged. Its ✕ appears only on such a row.
  final ValueChanged<int>? onRemoveSet;
  final ActiveSession? session;
  final LastPerformance? last;
  final Future<void> Function(int setNumber) onUndoSet;

  /// Where the typed kg and reps live. Owned by the logger screen, because
  /// the footer button reads the active row out of it.
  final SetDrafts drafts;

  /// Which unit every weight here is shown in and typed in.
  final WeightUnit unit;

  /// The set about to be done -- the lowest with nothing stored against it,
  /// or null once the exercise is finished. Handed in rather than worked out
  /// here: the footer button names this same set ("Complete set 3"), and the
  /// logger screen derives it once so the highlighted row and the button
  /// cannot disagree. A panel built without it highlights nothing.
  final int? activeSetNumber;

  /// Resolves the exercise's artwork. Empty renders the equipment-icon
  /// fallback, which is what a panel built without a repository shows.
  final String baseUrl;

  /// The exercise's looping demo, which the set table's tile plays. The
  /// logger passes the URL the demo stage already loaded; null keeps the
  /// tile still.
  final String? animationUrl;

  /// Null renders the header's toggle inert rather than absent, on the same
  /// reasoning as [onOpenDemo] below.
  final ValueChanged<WeightUnit>? onUnitChanged;

  /// Opens the same demo and cues the library's ⓘ shows, mid-workout.
  /// Null renders the affordance disabled rather than hiding it, so the
  /// header row's layout stays identical whether or not a caller wires it up.
  final VoidCallback? onOpenDemo;

  @override
  State<ExerciseLogPanel> createState() => _ExerciseLogPanelState();
}

class _ExerciseLogPanelState extends State<ExerciseLogPanel> {
  /// Whether the user has asked for a weight field on an exercise that does
  /// not normally take one -- a dip belt, a weighted vest.
  ///
  /// Asked for once on the exercise rather than per set: nobody belts up for
  /// set 2 alone. UI state, not storage -- nothing new is persisted to
  /// remember it, and [_showWeight] explains what stands in.
  bool _weightAdded = false;

  /// True while one of this exercise's fields has focus -- on a phone, while
  /// the keyboard is up. The tile freezes its animation then, so a loop
  /// does not pull the eye from the number being typed. Focus, not
  /// MediaQuery.viewInsets: the logger's Scaffold strips the keyboard inset
  /// from its body, so the panel would never see it.
  bool _typing = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChanged);
    super.dispose();
  }

  void _onFocusChanged() {
    final focused = FocusManager.instance.primaryFocus?.context;
    final typing =
        focused != null &&
        focused.findAncestorStateOfType<_ExerciseLogPanelState>() == this;
    if (mounted && typing != _typing) setState(() => _typing = typing);
  }

  /// Whether the set table has a weight column at all.
  ///
  /// Three ways to have one, and only the first is the common case:
  ///
  /// - the exercise is loaded, so the column is simply the table;
  /// - the user asked for it, on this exercise, this session;
  /// - or last session's set on this exercise carried a weight, which keeps
  ///   weighted pull-ups weighted week to week without storing a preference
  ///   for it. A null there is a bodyweight set rather than a missing
  ///   reading, so it reads as "no belt last time", which is what it was.
  bool get _showWeight =>
      !widget.exercise.isBodyweight ||
      _weightAdded ||
      widget.last?.weightKg != null;

  /// The logger rebuilds this panel in place as the workout moves, so the
  /// reveal has to be dropped explicitly -- left standing, one exercise's dip
  /// belt would follow the user onto the next exercise's push-ups.
  ///
  /// No setState: didUpdateWidget runs as part of this element's rebuild, so
  /// build() reads the cleared flag on the way through. Same shape as
  /// LoggerAction's handling of a failed set.
  @override
  void didUpdateWidget(ExerciseLogPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.exercise.exerciseId != oldWidget.exercise.exerciseId) {
      _weightAdded = false;
    }
  }

  /// The mockup's single mono line under the exercise name.
  String get _targetLine {
    final exercise = widget.exercise;
    final target = 'Target: ${exercise.prescription}';
    final previous = widget.last?.weightKg;
    if (previous == null) return target;
    return '$target · last ${formatWeightWithUnit(previous, widget.unit)}';
  }

  /// How much heavier this session's best set is than the last session's, or
  /// null when there is nothing to compare or nothing to celebrate.
  ///
  /// Strictly greater: equalling last week is not progressive overload, and a
  /// nudge that fires every session stops meaning anything.
  double? get _overload {
    final previous = widget.last?.weightKg;
    final current = widget.session;
    if (previous == null || current == null) return null;

    double? best;
    for (final set in current.sets) {
      if (set.exerciseId != widget.exercise.exerciseId ||
          set.weightKg == null) {
        continue;
      }
      if (best == null || set.weightKg! > best) best = set.weightKg;
    }
    if (best == null || best <= previous) return null;
    return best - previous;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final exercise = widget.exercise;
    final showWeight = _showWeight;
    final rows = widget.setCount ?? exercise.targetSets;
    // Only the last row, and only one added past the target that has not
    // been logged: rows come off the end, and a logged set is the record --
    // reopening it is how it changes.
    final removable =
        widget.onRemoveSet != null &&
            rows > exercise.targetSets &&
            widget.session?.setFor(exercise.exerciseId, rows) == null
        ? rows
        : null;
    // The table widens its mark column for the ✕ while it holds added rows,
    // not just while one is removable, so logging an added set does not
    // shift the columns under the user's thumb.
    final trailingWidth =
        widget.onRemoveSet != null && rows > exercise.targetSets
        ? SetRow.removeWidth
        : SetRow.tickWidth;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FsCard(
          key: Key('logpanel.${exercise.exerciseId}'),
          // Flush: the mockup's card has no padding of its own, so the header
          // and the table can carry their own and the table can run to the
          // card's edges.
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                // No bottom: those 14 dp are the column header's top padding
                // now, where the unit switch's taps can reach into them.
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                child: Row(
                  children: [
                    // The movement stays in view while logging: the tile plays
                    // the demo's own animation (72 dp, big enough to read the
                    // shape of it), and a tap still opens the full demo.
                    Semantics(
                      container: true,
                      button: true,
                      enabled: widget.onOpenDemo != null,
                      label: 'Watch how to do ${exercise.name}',
                      child: InkWell(
                        key: Key('logpanel.demo.${exercise.exerciseId}'),
                        onTap: widget.onOpenDemo,
                        borderRadius: BorderRadius.circular(FsRadius.md),
                        child: ExcludeSemantics(
                          // Frozen in place while a field has focus, rather
                          // than swapped for the still: Image honours
                          // TickerMode, and a swap can flash blank.
                          child: TickerMode(
                            key: const Key('logpanel.demo.ticker'),
                            enabled: !_typing,
                            child: ExerciseThumb(
                              size: 72,
                              radius: FsRadius.md,
                              baseUrl: widget.baseUrl,
                              thumbnailUrl: exercise.thumbnailUrl,
                              animationUrl: widget.animationUrl,
                              animate: true,
                              equipment: exercise.equipment,
                              // The artwork is the way into the demo, so it says
                              // so -- in a corner, clear of the movement.
                              overlayAlignment: Alignment.bottomRight,
                              overlay: Container(
                                margin: const EdgeInsets.all(4),
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: t.bg.withValues(alpha: 0.7),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.open_in_full,
                                  size: 13,
                                  color: widget.onOpenDemo == null
                                      ? t.text3
                                      : t.text,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            exercise.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.3,
                              color: t.text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _targetLine,
                            style: TextStyle(
                              fontFamily: fsMonoFamily,
                              fontSize: 11,
                              color: t.text3,
                            ),
                          ),
                          if (exercise.coaching != null) ...[
                            const SizedBox(height: 4),
                            CoachingTag(
                              key: const Key('coaching.tag.header'),
                              injuryName: exercise.coaching!.injuryName,
                            ),
                          ],
                          // On the exercise rather than in the table: the
                          // column it restores belongs to every set, and the
                          // table's own header row has no width to spare for
                          // a control once the weight column is gone.
                          if (!showWeight)
                            InkWell(
                              key: const Key('logpanel.addweight'),
                              onTap: () => setState(() => _weightAdded = true),
                              borderRadius: BorderRadius.circular(FsRadius.sm),
                              // A caption to look at, a 48 dp target to tap:
                              // the box grows around the text, which keeps
                              // its size and its place at the left.
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minWidth: 48,
                                  minHeight: 48,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  child: Align(
                                    alignment: AlignmentDirectional.centerStart,
                                    widthFactor: 1,
                                    heightFactor: 1,
                                    child: Text(
                                      '+ weight',
                                      style: TextStyle(
                                        fontFamily: fsMonoFamily,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: t.accentText,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                child: Column(
                  children: [
                    Padding(
                      key: const Key('logpanel.columns'),
                      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
                      // The unit switch is drawn about 19 dp tall in this
                      // row: the padding around it is the rest of its band,
                      // 14 above and 8 below. Nothing else here takes taps.
                      child: FsTapRoom(
                        reach: 14,
                        child: Row(
                          children: [
                            SizedBox(
                              width: SetRow.numberWidth,
                              // softWrap off to match .eyebrow's `white-space:
                              // nowrap`: at 10.5px with the eyebrow's tracking,
                              // "SET" otherwise wraps to two lines inside a
                              // 28px column and shoves the table down a row.
                              child: Text(
                                'SET',
                                softWrap: false,
                                overflow: TextOverflow.visible,
                                style: fsEyebrow(t),
                              ),
                            ),
                            // The weight heading, which is also the unit
                            // toggle. It goes with the column it names: this
                            // row shares SetRow's column constants, so a
                            // heading left standing over a column that is gone
                            // takes width the rows below no longer give it, and
                            // REPS slides off the field it labels.
                            //
                            // The toggle is not the only way to the unit --
                            // Settings owns it, and every other weight on the
                            // panel still reads in whatever it is set to.
                            if (showWeight) ...[
                              Expanded(
                                child: Center(
                                  // At 320 dp with large text the toggle is a
                                  // couple of pixels wider than its column;
                                  // shrink it there rather than overflow.
                                  child: _ScaleDown(
                                    child: FsUnitToggle(
                                      value: widget.unit,
                                      onChanged: widget.onUnitChanged,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: SetRow.columnGap),
                            ],
                            Expanded(
                              child: Center(
                                child: Text(
                                  'REPS',
                                  softWrap: false,
                                  overflow: TextOverflow.visible,
                                  style: fsEyebrow(t),
                                ),
                              ),
                            ),
                            const SizedBox(width: SetRow.columnGap),
                            SizedBox(width: trailingWidth),
                          ],
                        ),
                      ),
                    ),
                    for (var setNumber = 1; setNumber <= rows; setNumber++)
                      Builder(
                        builder: (context) {
                          final stored = widget.session?.setFor(
                            exercise.exerciseId,
                            setNumber,
                          );
                          // Seed on every build, which is what lets a prefill
                          // arriving from a fetch -- one frame after the table
                          // is first drawn -- still reach the fields.
                          //
                          // Authoritative exactly when the server holds the
                          // set: a stored value corrects the field, a prefill
                          // never does. See SetDrafts.seed.
                          widget.drafts.seed(
                            setNumber: setNumber,
                            // Not `stored?.weightKg ?? last?.weightKg`: a
                            // bodyweight set is STORED with a null weight, and
                            // `??` cannot tell that apart from having no stored
                            // set at all -- so it fell through to last session's
                            // number and wrote it into a read-only field.
                            weightKg: stored != null
                                ? stored.weightKg
                                : widget.last?.weightKg,
                            reps: stored != null
                                ? stored.reps
                                : widget.last?.reps,
                            unit: widget.unit,
                            authoritative: stored != null,
                          );
                          return SetRow(
                            key: ValueKey(
                              'set-${exercise.exerciseId}-$setNumber',
                            ),
                            setNumber: setNumber,
                            logged: stored,
                            drafts: widget.drafts,
                            unit: widget.unit,
                            showWeight: showWeight,
                            active: setNumber == widget.activeSetNumber,
                            repsHint: exercise.targetReps.isEmpty
                                ? 'reps'
                                : exercise.targetReps,
                            onReopen: () => widget.onUndoSet(setNumber),
                            trailingWidth: trailingWidth,
                            onRemove: setNumber == removable
                                ? () => widget.onRemoveSet!(setNumber)
                                : null,
                          );
                        },
                      ),
                    if (widget.onAddSet != null)
                      _AddSet(
                        exerciseName: exercise.name,
                        atCap: rows >= maxSetsPerExercise,
                        onAddSet: widget.onAddSet!,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_overload != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: t.accentDim,
              borderRadius: BorderRadius.circular(FsRadius.md),
              border: Border.all(color: t.accentLine),
            ),
            child: Row(
              children: [
                Icon(Icons.arrow_upward, size: 16, color: t.accentText),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '+${formatWeightWithUnit(_overload!, widget.unit)} vs last session'
                    ' — nice progressive overload.',
                    style: TextStyle(fontSize: 11, color: t.text),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// "+ Add set" under the set table, or why there is none once the table is
/// full.
class _AddSet extends StatelessWidget {
  const _AddSet({
    required this.exerciseName,
    required this.atCap,
    required this.onAddSet,
  });

  final String exerciseName;
  final bool atCap;
  final VoidCallback onAddSet;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    if (atCap) {
      // Said rather than greyed out: a disabled control with no reason reads
      // as broken.
      return Padding(
        key: const Key('logpanel.setCap'),
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        child: Text(
          '$maxSetsPerExercise sets is the most one exercise can hold.',
          style: TextStyle(fontSize: 12, color: t.text2, height: 1.35),
        ),
      );
    }

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        key: const Key('logpanel.addSet'),
        onPressed: onAddSet,
        icon: const Icon(Icons.add, size: 18),
        // The exercise is named for a screen reader, which reaches this
        // control without the card's heading in view.
        label: Text('Add set', semanticsLabel: 'Add a set to $exerciseName'),
        style: TextButton.styleFrom(
          foregroundColor: t.accentText,
          minimumSize: const Size(48, 48),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// A [FittedBox] that scales down without trimming its child's taps to its
/// own box. The unit switch's band reaches past the pill it draws, and a
/// plain FittedBox -- needed only at 320 dp with large text -- answered
/// inside the pill alone, whatever the room around it.
class _ScaleDown extends FittedBox {
  const _ScaleDown({required Widget super.child})
    : super(fit: BoxFit.scaleDown);

  @override
  RenderFittedBox createRenderObject(BuildContext context) =>
      _RenderScaleDown(textDirection: Directionality.maybeOf(context));
}

class _RenderScaleDown extends RenderFittedBox {
  _RenderScaleDown({super.textDirection}) : super(fit: BoxFit.scaleDown);

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    // Not the usual check against this box: the child's band lies outside
    // it. The scale still applies, through hitTestChildren's transform.
    if (!hitTestChildren(result, position: position)) return false;
    result.add(BoxHitTestEntry(this, position));
    return true;
  }
}
