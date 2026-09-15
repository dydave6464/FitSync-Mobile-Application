import 'package:flutter/widgets.dart';

import '../../../../core/units.dart';

/// The kg and reps being typed into one exercise's set table.
///
/// This used to live inside each row's State. It was lifted out when the
/// footer button became what logs a set: the button has to read the active
/// row's two fields, and a row's private State is not somewhere a sibling
/// widget can reach. The row renders; this holds what it renders.
///
/// One instance per exercise on screen. The logger disposes and rebuilds it
/// when the exercise changes, which is what makes a set number mean one thing.
class SetDrafts {
  final Map<int, TextEditingController> _weight = {};
  final Map<int, TextEditingController> _reps = {};

  TextEditingController weight(int setNumber) =>
      _weight.putIfAbsent(setNumber, TextEditingController.new);

  TextEditingController reps(int setNumber) =>
      _reps.putIfAbsent(setNumber, TextEditingController.new);

  /// Fills this set's fields from the last session, or from the set the
  /// server already holds.
  ///
  /// [authoritative] says which of those two it is, and the rule differs:
  ///
  /// A *prefill* fills empty fields only. It offers a starting point, it does
  /// not correct one: someone who started typing before
  /// `/sessions/last-performance` answered keeps what they typed, and a field
  /// they cleared on purpose stays clear.
  ///
  /// A *stored* set is not an offer, it is the record, and it overwrites.
  /// Without that, a field corrected while its write was in flight -- typing
  /// 105 over the 100 the button had already sent -- would survive the write
  /// landing, and the row would lock read-only showing a number the server
  /// does not hold. This is what SetRow's initState did before the fields
  /// moved out of the row, and losing it was the whole defect.
  ///
  /// Safe to call on every build either way: a field already reading what it
  /// is being seeded with is left alone, caret included.
  void seed({
    required int setNumber,
    double? weightKg,
    int? reps,
    required WeightUnit unit,
    bool authoritative = false,
  }) {
    if (weightKg != null) {
      final field = weight(setNumber);
      if (authoritative || field.text.isEmpty) {
        _write(field, formatWeight(weightKg, unit));
      }
    }
    if (reps != null) {
      final field = this.reps(setNumber);
      if (authoritative || field.text.isEmpty) _write(field, '$reps');
    }
  }

  /// Rewrites every weight typed under [from] to read in [to].
  ///
  /// Text typed under the old unit would otherwise sit there meaning something
  /// else entirely -- someone who typed 100 kg and then noticed the toggle was
  /// wrong would log 100 lb. Anything unparseable (an empty field, a lone
  /// decimal point mid-type) is left exactly as typed.
  void convert(WeightUnit from, WeightUnit to) {
    for (final field in _weight.values) {
      // Skip incomplete input like "12." or "." that ends with a decimal point.
      if (field.text.endsWith('.')) continue;
      final kg = parseWeight(field.text, from);
      if (kg == null) continue;
      _write(field, formatWeight(kg, to));
    }
  }

  /// Empties one set's fields -- what un-ticking a stored set needs, so the
  /// row does not keep showing the set that was just undone.
  void release(int setNumber) {
    _weight[setNumber]?.clear();
    _reps[setNumber]?.clear();
  }

  void dispose() {
    for (final field in _weight.values) {
      field.dispose();
    }
    for (final field in _reps.values) {
      field.dispose();
    }
    _weight.clear();
    _reps.clear();
  }

  /// Assigning `.text` alone drops the caret to offset 0, which puts it in
  /// front of a number the user may still be typing.
  ///
  /// Writing text the field already holds is skipped entirely: an
  /// authoritative seed runs on every build, and re-assigning the value each
  /// frame would notify the field's listeners -- and reset the caret -- for
  /// no change at all.
  void _write(TextEditingController controller, String text) {
    if (controller.text == text) return;
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
