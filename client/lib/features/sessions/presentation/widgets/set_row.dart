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
    this.onReopen,
  });

  /// Column geometry, shared with the panel's header row above it. Two
  /// hand-tuned numbers that happened to agree would drift the first time
  /// either changed.
  static const numberWidth = 28.0;
  static const columnGap = 10.0;
  static const tickWidth = 28.0;

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

  /// Reopens a stored set for editing. Null leaves the row inert.
  final VoidCallback? onReopen;

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
      hintStyle: TextStyle(
        fontFamily: fsMonoFamily,
        fontSize: 13,
        color: t.text3,
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

    return InkWell(
      key: Key('set.$setNumber.row'),
      // A stored row is the reopen target, and the whole row is it -- the
      // 28px mark this replaces was under Material's 48dp minimum, on the
      // control used most. An unlogged row has nothing to reopen.
      onTap: done ? onReopen : null,
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
                child: TextField(
                  key: Key('set.$setNumber.weight'),
                  controller: drafts.weight(setNumber),
                  enabled: editable,
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
              const SizedBox(width: SetRow.columnGap),
            ],
            Expanded(
              child: TextField(
                key: Key('set.$setNumber.reps'),
                controller: drafts.reps(setNumber),
                enabled: editable,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}')),
                ],
                decoration: decoration('reps'),
                style: TextStyle(
                  fontFamily: fsMonoFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: t.text,
                ),
              ),
            ),
            const SizedBox(width: SetRow.columnGap),
            SizedBox(
              key: Key('set.$setNumber.tick'),
              width: SetRow.tickWidth,
              child: SizedBox(height: 38, child: Center(child: _mark(t, done))),
            ),
          ],
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
