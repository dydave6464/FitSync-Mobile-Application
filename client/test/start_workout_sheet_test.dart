import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/exercises/presentation/exercise_list_screen.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/plans/presentation/generator_screen.dart';
import 'package:fitsync/features/plans/presentation/providers.dart';
import 'package:fitsync/features/plans/presentation/start_workout_sheet.dart';

/// The real face, not the test harness's. The default test font renders
/// FsTag('Recommended') at 136dp against Space Grotesk's ~62dp, which is
/// enough to invert a conclusion about whether this sheet fits.
Future<void> _loadFont() async {
  final bytes = await File('assets/fonts/SpaceGrotesk-Variable.ttf').readAsBytes();
  await (FontLoader('SpaceGrotesk')
        ..addFont(Future.value(ByteData.view(bytes.buffer))))
      .load();
}

Future<void> _open(
  WidgetTester tester, {
  WorkoutPlan? plan,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activePlanProvider.overrideWith((ref) async => plan),
      ],
      child: MaterialApp(
        theme: fsLightTheme(),
        // Above the Navigator on purpose: the sheet is a route, so a
        // MediaQuery under `home` would not reach it.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
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
  setUpAll(_loadFont);

  /// Both rows visible and hit-testable, which is what a clipped sheet
  /// costs: `showModalBottomSheet` caps its child at 9/16 of the screen and
  /// a bare Column has nowhere to put the remainder, so the second row goes
  /// off the bottom edge -- a debug stripe, and in release nothing at all.
  void expectBothRowsUsable(WidgetTester tester) {
    expect(find.byKey(const Key('start.generator')).hitTestable(), findsOneWidget);
    expect(find.byKey(const Key('start.manual')).hitTestable(), findsOneWidget);
  }

  testWidgets('both rows survive a landscape viewport', (tester) async {
    // 844x390: an iPhone 14 turned sideways. Every other test in this file
    // runs at the harness's 800x600, where 9/16 leaves room to spare.
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _open(tester);

    expectBothRowsUsable(tester);
  });

  testWidgets('both rows survive a small landscape viewport', (tester) async {
    // 640x360: the smallest Android phone the app targets, sideways.
    tester.view.physicalSize = const Size(640, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _open(tester);

    expectBothRowsUsable(tester);
  });

  testWidgets('the largest text scale scrolls rather than clipping',
      (tester) async {
    // 2.0x on a 390x844 phone -- Android's largest font setting. At this
    // scale the two rows are taller than the whole screen, so no cap and no
    // amount of full-height sheet can show both at once: the remainder has
    // to be reachable rather than cut off. (1.5x fits with the real face
    // loaded; it only overflows under the test harness's much wider default
    // font, which is why this file loads Space Grotesk.)
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _open(tester, textScaler: const TextScaler.linear(2));

    expect(find.byKey(const Key('start.generator')).hitTestable(), findsOneWidget);

    await tester.drag(find.byKey(const Key('start.generator')), const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('start.manual')).hitTestable(), findsOneWidget,
        reason: 'the second row must scroll into reach, not be clipped away');
  });

  testWidgets('the sheet offers both rows from the design', (tester) async {
    await _open(tester);

    expect(find.text('Start a workout'), findsOneWidget);
    expect(find.text('AI Workout Generator'), findsOneWidget);
    expect(find.text('Log manually'), findsOneWidget);
  });

  testWidgets('log manually is live now that the picker exists', (tester) async {
    // It was inert while the exercise library was a later slice. The library
    // and the sessions endpoint both exist now, so "Coming soon" would be
    // saying the capability is missing when it is not.
    await _open(tester);

    expect(find.text('Coming soon'), findsNothing);

    final row = tester.widget<InkWell>(
      find.byKey(const Key('start.manual')),
    );
    expect(row.onTap, isNotNull);
  });

  testWidgets('log manually opens the library to pick from', (tester) async {
    await _open(tester);

    await tester.tap(find.byKey(const Key('start.manual')));
    // Pumped rather than settled: the pushed list shows a progress indicator
    // while it fetches, and that animates forever, so pumpAndSettle would
    // wait out the timeout instead of the route transition.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final picker = tester.widget<ExerciseListScreen>(
      find.byType(ExerciseListScreen),
    );
    expect(picker.selecting, isTrue,
        reason: 'the same list, but picking rather than browsing');
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
