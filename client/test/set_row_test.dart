import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
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
