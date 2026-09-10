import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/plans/presentation/generator_screen.dart';
import 'package:fitsync/features/plans/presentation/providers.dart';
import 'package:fitsync/features/plans/presentation/start_workout_sheet.dart';

Future<void> _open(WidgetTester tester, {WorkoutPlan? plan}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activePlanProvider.overrideWith((ref) async => plan),
      ],
      child: MaterialApp(
        theme: fsLightTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showStartWorkoutSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the sheet offers both rows from the design', (tester) async {
    await _open(tester);

    expect(find.text('Start a workout'), findsOneWidget);
    expect(find.text('AI Workout Generator'), findsOneWidget);
    expect(find.text('Log manually'), findsOneWidget);
  });

  testWidgets('log manually is disabled and says so', (tester) async {
    // Slice 3 builds the exercise library. Until then the row is present and
    // inert, so the capability reads as planned rather than missing --
    // the same voice training_shell.dart's _ComingSoon already uses.
    await _open(tester);

    expect(find.text('Coming soon'), findsOneWidget);

    final row = tester.widget<InkWell>(
      find.byKey(const Key('start.manual')),
    );
    expect(row.onTap, isNull, reason: 'a disabled row must not be tappable');
  });

  testWidgets('the generator row is tappable', (tester) async {
    await _open(tester);

    final row = tester.widget<InkWell>(
      find.byKey(const Key('start.generator')),
    );
    expect(row.onTap, isNotNull);
  });

  testWidgets('the close button dismisses the sheet', (tester) async {
    await _open(tester);

    await tester.tap(find.byKey(const Key('start.close')));
    await tester.pumpAndSettle();
    expect(find.text('Start a workout'), findsNothing);
  });

  testWidgets('the generator row opens the generator', (tester) async {
    // find.text('AI Workout Generator') alone would pass even with a no-op
    // onTap: the row itself carries that label. Assert the screen actually
    // arrives.
    await _open(tester);

    await tester.tap(find.byKey(const Key('start.generator')));
    await tester.pumpAndSettle();

    expect(find.byType(GeneratorScreen), findsOneWidget);

    // The sheet must have been popped, not left stacked underneath: a
    // Navigator route that is merely covered by an opaque route above it
    // is still absent from find.text regardless of whether it was popped,
    // so the only way to tell the two apart is to go back and see what
    // resurfaces.
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Start a workout'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });
}
