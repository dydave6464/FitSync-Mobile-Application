// exercise_log_panel_test.dart is the extraction's safety net and must stay
// unmodified, so the new onOpenDemo affordance -- added after that file was
// written -- gets its own coverage here. Without this, onOpenDemo could be
// wired to nothing (or never rendered) and every test in the other file
// would still be green.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/exercises/presentation/exercise_thumb.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/sessions/domain/active_session.dart';
import 'package:fitsync/features/sessions/presentation/widgets/exercise_log_panel.dart';
import 'package:fitsync/features/sessions/presentation/widgets/set_drafts.dart';

const _exercise = PlanExercise(
  planExerciseId: 601,
  exerciseId: 101,
  name: 'Goblet squat',
  muscleGroup: 'quadriceps',
  orderNo: 1,
  targetSets: 3,
  targetReps: '8-12',
);

ActiveSession _session() => const ActiveSession(
  sessionId: 7,
  status: 'in_progress',
  sessionDate: '2026-09-08',
  sets: [],
);

Widget _host(Widget child) => MaterialApp(
  theme: fsLightTheme(),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

final _demoButton = find.byKey(const Key('logpanel.demo.101'));

/// A fresh store per test, torn down with the test.
SetDrafts _drafts(WidgetTester tester) {
  final drafts = SetDrafts();
  addTearDown(drafts.dispose);
  return drafts;
}

void main() {
  testWidgets('tapping the demo affordance invokes onOpenDemo', (tester) async {
    var opened = false;

    await tester.pumpWidget(
      _host(
        ExerciseLogPanel(
          exercise: _exercise,
          session: _session(),
          drafts: _drafts(tester),
          onUndoSet: (_) async {},
          onOpenDemo: () => opened = true,
        ),
      ),
    );

    await tester.tap(_demoButton);
    await tester.pumpAndSettle();

    expect(opened, isTrue);
  });

  testWidgets(
    'with no onOpenDemo, the affordance renders disabled rather than absent',
    (tester) async {
      await tester.pumpWidget(
        _host(
          ExerciseLogPanel(
            exercise: _exercise,
            session: _session(),
            drafts: _drafts(tester),
            onUndoSet: (_) async {},
          ),
        ),
      );

      // If onOpenDemo were ever wired to a hardcoded no-op instead of passed
      // straight through, this would still find the icon but onPressed would
      // no longer be null.
      final tile = tester.widget<InkWell>(_demoButton);
      expect(tile.onTap, isNull);
    },
  );

  // The teacher's request: the movement stays in view while logging. The
  // tile plays the same animation the demo stage already loaded.
  group('the animated tile', () {
    const gif = '/storage/exercises/101/anim.gif';
    final animation = find.byKey(const ValueKey('thumb.animation'));

    Widget panel(SetDrafts drafts, {VoidCallback? onOpenDemo}) => ExerciseLogPanel(
      exercise: _exercise,
      session: _session(),
      drafts: drafts,
      onUndoSet: (_) async {},
      onOpenDemo: onOpenDemo ?? () {},
      baseUrl: 'http://test.local',
      animationUrl: gif,
    );

    testWidgets('plays the animation at 72 dp', (tester) async {
      await tester.pumpWidget(_host(panel(_drafts(tester))));

      expect(animation, findsOneWidget);
      expect(
        (tester.widget<Image>(animation).image as NetworkImage).url,
        'http://test.local$gif',
      );
      expect(tester.getSize(find.byType(ExerciseThumb)), const Size(72, 72));
    });

    // Typing a number with a loop moving beside the field pulls the eye; the
    // tile holds still while one of the panel's fields has focus (the
    // keyboard is up) and plays again once it is dismissed.
    testWidgets('holds still while a set field is being typed into', (tester) async {
      await tester.pumpWidget(_host(panel(_drafts(tester))));
      expect(animation, findsOneWidget);

      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      expect(animation, findsNothing);

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(animation, findsOneWidget);
    });

    testWidgets('says what it opens, and still opens the demo', (tester) async {
      var opened = false;
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(panel(_drafts(tester), onOpenDemo: () => opened = true)));

      expect(
        tester.getSemantics(_demoButton),
        isSemantics(isButton: true, label: 'Watch how to do Goblet squat'),
      );
      expect(find.byIcon(Icons.open_in_full), findsOneWidget);

      await tester.tap(_demoButton);
      await tester.pumpAndSettle();
      expect(opened, isTrue);
      handle.dispose();
    });

    testWidgets('with no demo to open, the tile is announced as disabled', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(ExerciseLogPanel(
        exercise: _exercise,
        session: _session(),
        drafts: _drafts(tester),
        onUndoSet: (_) async {},
        baseUrl: 'http://test.local',
        animationUrl: gif,
      )));

      expect(
        tester.getSemantics(_demoButton),
        isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
      );
      handle.dispose();
    });

    testWidgets('fits a 320 dp phone at large text', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: fsLightTheme(),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(320, 640), textScaler: TextScaler.linear(1.6)),
          child: Scaffold(body: SingleChildScrollView(child: panel(_drafts(tester)))),
        ),
      ));

      expect(tester.takeException(), isNull);
      expect(animation, findsOneWidget);
    });
  });
}
