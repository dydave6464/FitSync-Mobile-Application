import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/units.dart';
import 'package:fitsync/features/sessions/presentation/widgets/set_drafts.dart';

void main() {
  test('the same set number returns the same controller', () {
    final drafts = SetDrafts();
    addTearDown(drafts.dispose);

    expect(identical(drafts.weight(1), drafts.weight(1)), isTrue);
    expect(identical(drafts.weight(1), drafts.weight(2)), isFalse);
  });

  test('seeding fills an empty field', () {
    final drafts = SetDrafts();
    addTearDown(drafts.dispose);

    drafts.seed(setNumber: 1, weightKg: 22.5, reps: 10, unit: WeightUnit.kg);

    expect(drafts.weight(1).text, '22.5');
    expect(drafts.reps(1).text, '10');
  });

  // The rule the old _SetRowState carried: a prefill offers a starting point,
  // it does not correct one.
  test('seeding leaves a value already typed alone', () {
    final drafts = SetDrafts();
    addTearDown(drafts.dispose);

    drafts.weight(1).text = '30';
    drafts.reps(1).text = '6';
    drafts.seed(setNumber: 1, weightKg: 22.5, reps: 10, unit: WeightUnit.kg);

    expect(drafts.weight(1).text, '30');
    expect(drafts.reps(1).text, '6');
  });

  test('seeding formats the weight in the unit on screen', () {
    final drafts = SetDrafts();
    addTearDown(drafts.dispose);

    // 22.5 kg is 49.6039... lb.
    drafts.seed(setNumber: 1, weightKg: 22.5, reps: 10, unit: WeightUnit.lb);

    expect(drafts.weight(1).text, '49.6');
  });

  test('converting carries every typed weight across and leaves reps alone', () {
    final drafts = SetDrafts();
    addTearDown(drafts.dispose);

    drafts.weight(1).text = '100';
    drafts.reps(1).text = '8';

    drafts.convert(WeightUnit.kg, WeightUnit.lb);

    // 100 kg is 220.462... lb.
    expect(drafts.weight(1).text, '220.5');
    expect(drafts.reps(1).text, '8');
  });

  test('converting leaves an unparseable field exactly as typed', () {
    final drafts = SetDrafts();
    addTearDown(drafts.dispose);

    drafts.weight(1).text = '';
    drafts.weight(2).text = '12.';

    drafts.convert(WeightUnit.kg, WeightUnit.lb);

    expect(drafts.weight(1).text, '');
    expect(drafts.weight(2).text, '12.');
  });

  test('releasing a set clears it so the row starts empty again', () {
    final drafts = SetDrafts();
    addTearDown(drafts.dispose);

    drafts.weight(1).text = '30';
    drafts.release(1);

    expect(drafts.weight(1).text, '');
  });
}
