import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme.dart';
import '../../../../core/units.dart';
import '../../domain/active_session.dart';

/// One line of the set table: number, kg, reps, tick.
///
/// Write-through, not optimistic. The row disables while the write is in
/// flight and only ticks once [onComplete] returns, so a visible tick always
/// means a stored set. A failure shows a retry on this row alone and leaves
/// every other set untouched.
class SetRow extends StatefulWidget {
  const SetRow({
    super.key,
    required this.setNumber,
    required this.logged,
    required this.onComplete,
    required this.onUndo,
    this.prefillWeightKg,
    this.prefillReps,
    this.unit = WeightUnit.kg,
    this.active = false,
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

  /// Seeded from the last session's heaviest set, when there was one.
  final double? prefillWeightKg;

  /// The reps of that same set. Separate from [prefillWeightKg] because a
  /// bodyweight exercise has the one without the other.
  final int? prefillReps;

  final Future<void> Function(double? weightKg, int? reps) onComplete;
  final Future<void> Function() onUndo;

  /// What the field shows and how its text is read back. Stored values are
  /// kilograms either way -- see [WeightUnit].
  final WeightUnit unit;

  /// The set about to be done: the first one with nothing logged against it.
  /// Drawn in accent, which is the only thing on the table saying which row
  /// is next -- every empty row is otherwise identical.
  final bool active;

  @override
  State<SetRow> createState() => _SetRowState();
}

class _SetRowState extends State<SetRow> {
  late final TextEditingController _weight;
  late final TextEditingController _reps;
  bool _busy = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final logged = widget.logged;
    final kg = logged?.weightKg ?? widget.prefillWeightKg;
    final reps = logged?.reps ?? widget.prefillReps;
    _weight = TextEditingController(
      text: kg == null ? '' : formatWeight(kg, widget.unit),
    );
    _reps = TextEditingController(text: reps?.toString() ?? '');
  }

  /// Two things can reach the fields after this State exists: a unit change
  /// and the arrival of the last session's numbers. Both are handled here
  /// rather than in [initState] because the row is keyed on the stored set's
  /// presence, so neither of them rebuilds this State.
  @override
  void didUpdateWidget(SetRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Order matters: converting first leaves any value the prefill then seeds
    // to be formatted in the new unit once, rather than converted twice.
    if (oldWidget.unit != widget.unit) _convertWeight(oldWidget.unit);
    _seedFromPrefill(oldWidget);
  }

  /// Carries a value already in the field across a unit change.
  ///
  /// Text typed under the old unit would otherwise sit there meaning something
  /// else entirely. Anything unparseable (an empty field, a lone decimal point
  /// mid-type) is left exactly as typed.
  void _convertWeight(WeightUnit from) {
    final kg = parseWeight(_weight.text, from);
    if (kg == null) return;
    _write(_weight, formatWeight(kg, widget.unit));
  }

  /// Seeds the fields once the last session's numbers arrive.
  ///
  /// They come from a fetch, so the logger's first frame always builds this row
  /// with nothing to prefill -- and since the row is keyed on the stored set's
  /// presence, the rebuild that brings them in reuses this State and never runs
  /// [initState] again. Reading them there alone left the header saying "last
  /// 22.5 kg" above two empty fields, and repeating a workout meant typing
  /// every number the app already knew.
  ///
  /// Into an empty field only, and only on the frame the value changes: a
  /// prefill offers a starting point, it does not correct one. Someone who
  /// started typing before the fetch landed keeps what they typed, and a field
  /// they deliberately cleared stays clear.
  void _seedFromPrefill(SetRow oldWidget) {
    // A stored set owns its fields; they are read-only and already show it.
    if (widget.logged != null) return;

    final kg = widget.prefillWeightKg;
    if (kg != null && kg != oldWidget.prefillWeightKg && _weight.text.isEmpty) {
      _write(_weight, formatWeight(kg, widget.unit));
    }
    final reps = widget.prefillReps;
    if (reps != null && reps != oldWidget.prefillReps && _reps.text.isEmpty) {
      _write(_reps, '$reps');
    }
  }

  /// Assigning `.text` alone drops the cursor to offset 0, which puts the
  /// caret in front of a number the user may still be typing.
  void _write(TextEditingController controller, String text) {
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  void dispose() {
    _weight.dispose();
    _reps.dispose();
    super.dispose();
  }

  Future<void> _tick() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      if (widget.logged != null) {
        await widget.onUndo();
      } else {
        // An empty field is "not recorded", never zero.
        await widget.onComplete(
          parseWeight(_weight.text, widget.unit),
          int.tryParse(_reps.text.trim()),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final done = widget.logged != null;
    final editable = !done && !_busy;

    InputDecoration decoration(String hint) => InputDecoration(
          hintText: hint,
          isDense: true,
          filled: true,
          fillColor: widget.active ? t.accentDim : t.surface2,
          contentPadding: const EdgeInsets.symmetric(vertical: 9),
          hintStyle: TextStyle(
            fontFamily: fsMonoFamily, fontSize: 13, color: t.text3,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SetRow.cellRadius),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SetRow.cellRadius),
            borderSide: BorderSide(
              color: widget.active ? t.accentLine : Colors.transparent,
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: SetRow.numberWidth,
            child: Text(
              '${widget.setNumber}',
              style: TextStyle(
                fontFamily: fsMonoFamily,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: t.text3,
              ),
            ),
          ),
          Expanded(
            child: TextField(
              key: Key('set.${widget.setNumber}.weight'),
              controller: _weight,
              enabled: editable,
              textAlign: TextAlign.center,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                // Three digits and two decimals: weight_kg is DECIMAL(6,2) and
                // the server rejects anything above 999.99 anyway.
                FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}\.?\d{0,2}')),
              ],
              decoration: decoration(widget.unit.api),
              style: TextStyle(
                fontFamily: fsMonoFamily,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: t.text,
              ),
            ),
          ),
          const SizedBox(width: SetRow.columnGap),
          Expanded(
            child: TextField(
              key: Key('set.${widget.setNumber}.reps'),
              controller: _reps,
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
          // Failure widens the column: Retry is a word, and an error state is
          // the one place the mockup's 28px mark cannot carry the meaning.
          SizedBox(
            width: _failed ? 74 : SetRow.tickWidth,
            child: _failed
                ? TextButton(
                    key: Key('set.${widget.setNumber}.tick'),
                    onPressed: _busy ? null : _tick,
                    child: const Text('Retry'),
                  )
                : InkWell(
                    key: Key('set.${widget.setNumber}.tick'),
                    onTap: _busy ? null : _tick,
                    customBorder: const CircleBorder(),
                    child: SizedBox(
                      height: 38,
                      child: Center(child: _mark(t, done)),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// The mockup's two states: an accent check once the set is stored, and an
  /// empty ring before that.
  Widget _mark(FsTokens t, bool done) {
    if (_busy) {
      return const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
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
