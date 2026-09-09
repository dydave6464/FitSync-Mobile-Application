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
    _weight = TextEditingController(
      text: logged?.weightKg != null
          ? formatWeight(logged!.weightKg!, widget.unit)
          : widget.prefillWeightKg != null
              ? formatWeight(widget.prefillWeightKg!, widget.unit)
              : '',
    );
    _reps = TextEditingController(text: logged?.reps?.toString() ?? '');
  }

  /// Carries a value already in the field across a unit change.
  ///
  /// The row is keyed on the stored set's presence, not on the unit, so
  /// flipping kg/lb rebuilds this widget without rebuilding its State -- and
  /// text typed under the old unit would otherwise sit there meaning
  /// something else entirely. Anything unparseable (an empty field, a lone
  /// decimal point mid-type) is left exactly as typed.
  @override
  void didUpdateWidget(SetRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.unit == widget.unit) return;

    final kg = parseWeight(_weight.text, oldWidget.unit);
    if (kg == null) return;
    final converted = formatWeight(kg, widget.unit);
    _weight.value = TextEditingValue(
      text: converted,
      // Assigning `.text` alone drops the cursor to offset 0, which puts the
      // caret in front of a number the user may still be typing.
      selection: TextSelection.collapsed(offset: converted.length),
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
