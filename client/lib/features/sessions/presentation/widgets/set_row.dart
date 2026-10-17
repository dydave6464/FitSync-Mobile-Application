import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme.dart';
import '../../../../core/units.dart';
import '../../domain/active_session.dart';
import 'set_drafts.dart';

/// One line of the set table: number, kg, reps, mark -- or number, reps,
/// mark for an exercise that carries no external load.
///
/// Stateless, and deliberately inert. It renders what [drafts] holds and what
/// the server has stored; it does not log a set and does not own the text
/// being typed. The footer button is what writes -- see `logger_action.dart`.
class SetRow extends StatelessWidget {
  const SetRow({
    super.key,
    required this.setNumber,
    required this.logged,
    required this.drafts,
    this.unit = WeightUnit.kg,
    this.showWeight = true,
    this.active = false,
    this.repsHint = 'reps',
    this.onReopen,
    this.onRemove,
    this.trailingWidth = tickWidth,
  });

  /// Column geometry, shared with the panel's header row above it. Two
  /// hand-tuned numbers that happened to agree would drift the first time
  /// either changed.
  static const numberWidth = 28.0;
  static const columnGap = 10.0;
  static const tickWidth = 28.0;

  /// The trailing column while a set table holds an added row: wide enough
  /// for the ✕ that removes one to be a full 48 dp target. The whole table
  /// widens together, header included, so its columns stay in line.
  static const removeWidth = 48.0;

  /// The mockup's set cells are rounded 9px -- between FsRadius.sm and a
  /// square, and small enough that borrowing either reads as a different
  /// table. Local rather than a token because nothing else uses it.
  static const cellRadius = 9.0;

  final int setNumber;

  /// Non-null once the server holds this set.
  final LoggedSet? logged;

  final SetDrafts drafts;

  /// What the fields show and how their text is read back. Stored values are
  /// kilograms either way -- see [WeightUnit].
  final WeightUnit unit;

  /// Whether this set takes an external load at all.
  ///
  /// False drops the weight column outright rather than disabling it: a
  /// greyed-out field on every set of every pull-up is still a column of the
  /// table asking to be read. Reps takes the space. The panel's header row
  /// shares this row's column widths and has to drop its own weight heading
  /// in step -- see ExerciseLogPanel.
  final bool showWeight;

  /// The set about to be done: the first one with nothing logged against it.
  /// Drawn in accent, which is the only thing on the table saying which row
  /// is next -- every empty row is otherwise identical.
  final bool active;

  /// What the empty reps box says: the exercise's target range ("8-12") when
  /// there is one, so the number to aim for sits where it is typed.
  final String repsHint;

  /// Reopens a stored set for editing. Null leaves the row inert.
  final VoidCallback? onReopen;

  /// Takes this row off the table: a set added past the target and not yet
  /// logged. Non-null puts a ✕ where the mark would be. Only the last such
  /// row carries it, so rows are only ever removed from the end.
  final VoidCallback? onRemove;

  /// How wide the mark's column is -- [tickWidth], or [removeWidth] while
  /// the table has an added row. See [removeWidth].
  final double trailingWidth;

  /// A touch anywhere but a text field -- the start of a scroll included --
  /// takes the cursor out of this one, which closes the keyboard and lets
  /// the tile play again. Flutter does that only for a mouse: a finger on a
  /// phone left the field focused, and the iPhone number pad has no key to
  /// close it. Another field is not "outside" -- text fields share a tap
  /// region -- so moving from weight to reps keeps the keyboard up.
  static void _letGo(PointerDownEvent event) =>
      FocusManager.instance.primaryFocus?.unfocus();

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final done = logged != null;
    // A stored set is the record and is not typed over; anything else is.
    // There is no in-flight lock here any more: the write happens at the
    // footer button, and the row that a write is landing on stays editable
    // until the set itself arrives -- at which point the panel re-seeds the
    // fields from what was actually stored. See SetDrafts.seed.
    final editable = !done;

    InputDecoration decoration(String hint) => InputDecoration(
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: active ? t.accentDim : t.surface2,
      contentPadding: const EdgeInsets.symmetric(vertical: 9),
      // text2, not text3: the reps hint is the target range, which is data
      // the user reads, and text3 fails contrast on these fills.
      hintStyle: TextStyle(
        fontFamily: fsMonoFamily,
        fontSize: 13,
        color: t.text2,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SetRow.cellRadius),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SetRow.cellRadius),
        borderSide: BorderSide(
          color: active ? t.accentLine : Colors.transparent,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SetRow.cellRadius),
        borderSide: BorderSide(color: t.accentLine),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SetRow.cellRadius),
        borderSide: BorderSide.none,
      ),
    );

    final reopens = done && onReopen != null;
    // Says what the tap does. Without it a screen reader announces the row as
    // a bare "2" that can be tapped, and the tap takes the set back.
    return Semantics(
      hint: reopens ? 'Reopen set $setNumber' : null,
      child: InkWell(
        key: Key('set.$setNumber.row'),
        // A stored row is the reopen target, and the whole row is it -- the
        // 28px mark this replaces was under Material's 48dp minimum, on the
        // control used most. An unlogged row has nothing to reopen.
        onTap: reopens ? onReopen : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          child: Row(
            children: [
              SizedBox(
                width: SetRow.numberWidth,
                child: Text(
                  '$setNumber',
                  style: TextStyle(
                    fontFamily: fsMonoFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: t.text3,
                  ),
                ),
              ),
              if (showWeight) ...[
                Expanded(
                  // Named for screen readers: the hint is only the unit, and it
                  // goes once a number is typed.
                  child: Semantics(
                    label: 'Weight',
                    child: TextField(
                      key: Key('set.$setNumber.weight'),
                      controller: drafts.weight(setNumber),
                      enabled: editable,
                      onTapOutside: _letGo,
                      textAlign: TextAlign.center,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        // Three digits and two decimals: weight_kg is DECIMAL(6,2)
                        // and the server rejects anything above 999.99 anyway.
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d{0,3}\.?\d{0,2}'),
                        ),
                      ],
                      decoration: decoration(unit.api),
                      style: TextStyle(
                        fontFamily: fsMonoFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: t.text,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: SetRow.columnGap),
              ],
              Expanded(
                child: Semantics(
                  label: 'Reps',
                  child: TextField(
                    key: Key('set.$setNumber.reps'),
                    controller: drafts.reps(setNumber),
                    enabled: editable,
                    onTapOutside: _letGo,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}')),
                    ],
                    decoration: decoration(repsHint),
                    style: TextStyle(
                      fontFamily: fsMonoFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: t.text,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: SetRow.columnGap),
              SizedBox(
                key: Key('set.$setNumber.tick'),
                width: trailingWidth,
                child: onRemove != null && !done
                    ? IconButton(
                        key: Key('set.$setNumber.remove'),
                        // The tooltip is also the button's name for a screen
                        // reader, which a bare ✕ would not have.
                        tooltip: 'Remove set $setNumber',
                        onPressed: onRemove,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 48,
                          height: 48,
                        ),
                        icon: Icon(Icons.close, size: 18, color: t.text2),
                      )
                    // As tall as the ✕ while the table is wide enough for
                    // one, so every row keeps one height and the table does
                    // not jump as the ✕ moves up a row or goes.
                    : SizedBox(
                        height: trailingWidth == SetRow.removeWidth ? 48 : 38,
                        child: Center(child: _mark(t, done)),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The mockup's two states: an accent check once the set is stored, and an
  /// empty ring before that.
  Widget _mark(FsTokens t, bool done) {
    if (done) return Icon(Icons.check, size: 16, color: t.accent);
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: t.line2, width: 2),
      ),
    );
  }
}
