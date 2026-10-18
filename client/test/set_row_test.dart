import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/units.dart';
import 'package:fitsync/features/sessions/domain/active_session.dart';
import 'package:fitsync/features/sessions/presentation/widgets/set_drafts.dart';
import 'package:fitsync/features/sessions/presentation/widgets/set_row.dart';

/// Fixed width, because two of these tests compare the reps field's size
/// between the row's two shapes -- a host that sized itself to its content
/// would make that comparison meaningless.
Widget _host(Widget child) => MaterialApp(
  theme: fsLightTheme(),
  home: Scaffold(
    body: Center(child: SizedBox(width: 360, child: child)),
  ),
);

SetDrafts _drafts(WidgetTester tester) {
  final drafts = SetDrafts();
  addTearDown(drafts.dispose);
  return drafts;
}

void main() {
  // The default is the loaded row: everything that already builds a SetRow
  // means this one, and the flag is what the bodyweight case opts out of.
  testWidgets('a row offers a weight field by default', (tester) async {
    await tester.pumpWidget(
      _host(SetRow(setNumber: 1, logged: null, drafts: _drafts(tester))),
    );

    expect(find.byKey(const Key('set.1.weight')), findsOneWidget);
    expect(find.byKey(const Key('set.1.reps')), findsOneWidget);
  });

  // Dropped, not disabled. A greyed-out field on every set of every pull-up
  // is still a column of the table asking to be read.
  testWidgets('without a weight column the row offers no weight field', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        SetRow(
          setNumber: 1,
          logged: null,
          drafts: _drafts(tester),
          showWeight: false,
        ),
      ),
    );

    expect(find.byKey(const Key('set.1.weight')), findsNothing);
    // What the row is still for: counting reps and marking the set done.
    expect(find.byKey(const Key('set.1.reps')), findsOneWidget);
    expect(find.byKey(const Key('set.1.tick')), findsOneWidget);
  });

  // The freed space goes to reps rather than to an empty gap where the
  // column used to be -- which is what a row hiding the field but keeping
  // its Expanded would leave behind.
  testWidgets('reps takes the space the weight column leaves', (tester) async {
    Future<double> repsWidth({required bool showWeight}) async {
      await tester.pumpWidget(
        _host(
          SetRow(
            setNumber: 1,
            logged: null,
            drafts: _drafts(tester),
            showWeight: showWeight,
          ),
        ),
      );
      return tester.getSize(find.byKey(const Key('set.1.reps'))).width;
    }

    final shared = await repsWidth(showWeight: true);
    final alone = await repsWidth(showWeight: false);

    expect(alone, greaterThan(shared));
  });
  // The whole logged row is a button that reopens the set; a screen reader
  // has to say so, or the tap that undoes a set is a surprise.
  // The tick is what says the set is stored, so it is read like a word: the
  // brand green is 2.9:1 on white, under the 3:1 a meaningful icon needs.
  testWidgets("a logged set's tick is drawn in the text green", (tester) async {
    await tester.pumpWidget(
      _host(
        SetRow(
          setNumber: 2,
          logged: const LoggedSet(
            exerciseId: 1,
            setNumber: 2,
            weightKg: 20,
            reps: 8,
          ),
          drafts: _drafts(tester),
          onReopen: () {},
        ),
      ),
    );

    final tick = find.byIcon(Icons.check);
    expect(tester.widget<Icon>(tick).color, tester.element(tick).fs.accentText);
  });

  testWidgets('a logged row tells a screen reader it reopens the set', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        SetRow(
          setNumber: 2,
          logged: const LoggedSet(
            exerciseId: 1,
            setNumber: 2,
            weightKg: 20,
            reps: 8,
          ),
          drafts: _drafts(tester),
          onReopen: () {},
        ),
      ),
    );

    expect(
      tester.getSemantics(find.byKey(const Key('set.2.row'))),
      isSemantics(hint: 'Reopen set 2', hasTapAction: true),
    );
    handle.dispose();
  });

  // "+ Add set" widens the table's mark column for a 48 dp ✕. The rows must
  // not grow with it: a table that jumps 10 dp per row as a set is added
  // moves every field from under the thumb about to tap it.
  testWidgets('a row is as tall with the remove column as without it', (
    tester,
  ) async {
    Future<double> rowHeight({required bool removable}) async {
      await tester.pumpWidget(
        _host(
          SetRow(
            setNumber: 4,
            logged: null,
            drafts: _drafts(tester),
            trailingWidth: removable ? SetRow.removeWidth : SetRow.tickWidth,
            onRemove: removable ? () {} : null,
          ),
        ),
      );
      return tester.getSize(find.byKey(const Key('set.4.row'))).height;
    }

    final plain = await rowHeight(removable: false);
    final withRemove = await rowHeight(removable: true);

    expect(withRemove, plain);
    // Still a full target, inside the row rather than stretching it.
    final remove = tester.getSize(find.byKey(const Key('set.4.remove')));
    expect(remove.width, greaterThanOrEqualTo(48));
    expect(remove.height, greaterThanOrEqualTo(48));
  });

  // One sentence per logged set, rather than a bare "2", two read-only
  // fields and an unlabelled check read out one by one.
  testWidgets('a logged row reads as one sentence', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        SetRow(
          setNumber: 2,
          logged: const LoggedSet(
            exerciseId: 1,
            setNumber: 2,
            weightKg: 60,
            reps: 8,
          ),
          drafts: _drafts(tester),
          onReopen: () {},
        ),
      ),
    );

    expect(
      tester.getSemantics(find.byKey(const Key('set.2.row'))),
      isSemantics(
        label: 'Set 2, 60 kg, 8 reps, logged',
        hint: 'Reopen set 2',
        hasTapAction: true,
      ),
    );
    // The sentence replaces the fragments rather than adding to them.
    expect(find.bySemanticsLabel('2'), findsNothing);
    handle.dispose();
  });

  // In the unit on screen, and without a weight it never had.
  testWidgets('a logged bodyweight set in lb leaves the weight out', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        SetRow(
          setNumber: 1,
          logged: const LoggedSet(exerciseId: 1, setNumber: 1, reps: 12),
          drafts: _drafts(tester),
          unit: WeightUnit.lb,
          onReopen: () {},
        ),
      ),
    );

    expect(
      tester.getSemantics(find.byKey(const Key('set.1.row'))).label,
      'Set 1, 12 reps, logged',
    );
    handle.dispose();
  });

  // An open row is still two fields to type in, so it stays two nodes; the
  // row says which set they belong to, and whether it is the next one.
  testWidgets('an open row names its set and keeps its fields', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        Column(
          children: [
            SetRow(setNumber: 1, logged: null, drafts: _drafts(tester)),
            SetRow(
              setNumber: 2,
              logged: null,
              drafts: _drafts(tester),
              active: true,
            ),
          ],
        ),
      ),
    );

    // By label: the row's node is the container above the InkWell, which
    // keeps a node of its own for the fields under it.
    expect(find.bySemanticsLabel('Set 1, not logged yet'), findsOneWidget);
    expect(find.bySemanticsLabel('Set 2, up next'), findsOneWidget);
    String fieldLabel(String key) => tester
        .getSemantics(
          find.descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(EditableText),
          ),
        )
        .label;
    expect(fieldLabel('set.2.weight'), contains('Weight'));
    expect(fieldLabel('set.2.reps'), contains('Reps'));
    handle.dispose();
  });

  testWidgets('an unlogged row offers nothing to reopen', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(SetRow(setNumber: 2, logged: null, drafts: _drafts(tester))),
    );

    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.hint == 'Reopen set 2',
      ),
      findsNothing,
    );
    handle.dispose();
  });
}
