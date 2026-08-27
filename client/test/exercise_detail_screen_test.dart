import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` is not part of the main flutter_riverpod.dart barrel export in
// 3.4.2 — it moved under misc.dart. Needed here only for the harness
// helper's parameter type below.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/features/exercises/domain/exercise.dart';
import 'package:fitsync/features/exercises/presentation/exercise_detail_screen.dart';
import 'package:fitsync/features/exercises/presentation/providers.dart';

const _detail = ExerciseDetail(
  exerciseId: 1,
  name: '3/4 sit-up',
  muscleGroup: 'abs',
  equipment: 'body weight',
  thumbnailUrl: '/storage/exercises/0001/thumb.jpg',
  animationUrl: '/storage/exercises/0001/animation.gif',
  cues: ['Lie flat on your back.', 'Curl forward.'],
);

Widget harness(Override override) => ProviderScope(
      overrides: [override],
      child: const MaterialApp(home: ExerciseDetailScreen(exerciseId: 1)),
    );

// The default flutter_test surface is 800x600 logical px — wider than it is
// tall, unlike any phone this app targets. The detail screen's hero image is
// AspectRatio(1) at the ListView's ~768px width, so on the default surface
// alone it is already ~768px tall: taller than the whole viewport. That
// pushes the chips and cues below the SliverList's lazy-build window, so
// they are never mounted and `find` cannot see them — not a rendering bug,
// just an unrepresentative test surface. A portrait phone-sized surface
// gives the square image a sane height and matches real usage.
void _usePortraitSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('renders the name, metadata and numbered cues', (tester) async {
    _usePortraitSurface(tester);
    await tester.pumpWidget(harness(
      exerciseDetailProvider(1).overrideWith((ref) async => _detail),
    ));
    await tester.pumpAndSettle();

    expect(find.text('3/4 sit-up'), findsOneWidget);
    expect(find.textContaining('abs'), findsWidgets);
    expect(find.text('1. Lie flat on your back.'), findsOneWidget);
    expect(find.text('2. Curl forward.'), findsOneWidget);
  });

  testWidgets('surfaces the server error message with a retry', (tester) async {
    _usePortraitSurface(tester);
    await tester.pumpWidget(harness(
      exerciseDetailProvider(1).overrideWith(
        (ref) async => throw const ApiException('EXERCISE_NOT_FOUND', 'No live exercise with id 1.'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('No live exercise with id 1.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('an unreachable animation does not crash the screen', (tester) async {
    _usePortraitSurface(tester);
    await tester.pumpWidget(harness(
      exerciseDetailProvider(1).overrideWith((ref) async => _detail),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('3/4 sit-up'), findsOneWidget);
  });
}
