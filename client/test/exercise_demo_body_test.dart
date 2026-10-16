import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/exercises/domain/exercise.dart';
import 'package:fitsync/features/exercises/presentation/widgets/exercise_demo_body.dart';

const _base = 'http://test.local';
const _thumb = '/storage/exercises/0001/thumb.jpg';
const _gif = '/storage/exercises/0001/animation.gif';

const _detail = ExerciseDetail(
  exerciseId: 1,
  name: '3/4 sit-up',
  muscleGroup: 'abs',
  equipment: 'body weight',
  thumbnailUrl: _thumb,
  animationUrl: _gif,
  cues: ['Lie flat on your back.', 'Curl forward.'],
);

Widget _harness({
  ExerciseDetail exercise = _detail,
  bool reduceMotion = false,
  double textScale = 1,
}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      disableAnimations: reduceMotion,
      textScaler: TextScaler.linear(textScale),
    ),
    child: child!,
  ),
  home: Scaffold(
    body: ExerciseDemoBody(exercise: exercise, baseUrl: _base),
  ),
);

/// Every [Image] showing [url], whatever state its load is in. In a widget
/// test the network never answers with pixels, so the Image widget itself --
/// not what it painted -- is the evidence of what the body chose to show.
Finder _imageOf(String path) => find.byWidgetPredicate(
  (w) =>
      w is Image &&
      w.image is NetworkImage &&
      (w.image as NetworkImage).url == '$_base$path',
);

void _useSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Whether [finder]'s widget is allowed to advance frames. Image only listens
/// to its stream -- and so only animates -- while TickerMode is on.
bool _ticking(WidgetTester tester, Finder finder) =>
    TickerMode.valuesOf(tester.element(finder)).enabled;

void main() {
  testWidgets('with Reduce Motion on, shows the still picture and a play '
      'button instead of the animation', (tester) async {
    _useSurface(tester, const Size(390, 844));
    await tester.pumpWidget(_harness(reduceMotion: true));
    await tester.pump();

    expect(_imageOf(_thumb), findsOneWidget);
    expect(_imageOf(_gif), findsNothing);
    expect(find.bySemanticsLabel('Play demo'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Play demo'));
    await tester.pump();

    expect(_imageOf(_gif), findsOneWidget);
    expect(_ticking(tester, _imageOf(_gif)), isTrue);
    expect(find.bySemanticsLabel('Pause demo'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
  });

  testWidgets('tapping the demo pauses it and tapping again resumes', (
    tester,
  ) async {
    _useSurface(tester, const Size(390, 844));
    await tester.pumpWidget(_harness());
    await tester.pump();

    expect(_imageOf(_gif), findsOneWidget);
    expect(_ticking(tester, _imageOf(_gif)), isTrue);
    expect(find.bySemanticsLabel('Pause demo'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);

    await tester.tap(find.bySemanticsLabel('Pause demo'));
    await tester.pump();

    // Paused holds the current frame rather than swapping back to the still.
    expect(_imageOf(_gif), findsOneWidget);
    expect(_ticking(tester, _imageOf(_gif)), isFalse);
    expect(find.bySemanticsLabel('Play demo'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Play demo'));
    await tester.pump();

    expect(_ticking(tester, _imageOf(_gif)), isTrue);
    expect(find.bySemanticsLabel('Pause demo'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
  });

  testWidgets('the play/pause control is at least 48 dp', (tester) async {
    _useSurface(tester, const Size(390, 844));
    await tester.pumpWidget(_harness());
    await tester.pump();

    final size = tester.getSize(find.bySemanticsLabel('Pause demo'));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  });

  testWidgets('shows the still picture while the animation has no frame yet', (
    tester,
  ) async {
    _useSurface(tester, const Size(390, 844));
    await tester.pumpWidget(_harness());

    // First frame: the GIF has been asked for but nothing has arrived.
    expect(_imageOf(_gif), findsOneWidget);
    expect(_imageOf(_thumb), findsOneWidget);
  });

  testWidgets('never blows the demo up past 540 wide, and centres it', (
    tester,
  ) async {
    _useSurface(tester, const Size(1200, 1600));
    await tester.pumpWidget(_harness());
    await tester.pump();

    final rect = tester.getRect(_imageOf(_gif));
    expect(rect.width, lessThanOrEqualTo(540));
    expect(rect.center.dx, closeTo(600, 1));
  });

  testWidgets('without a thumbnail, Reduce Motion still holds the animation '
      'paused behind a play button', (tester) async {
    _useSurface(tester, const Size(390, 844));
    await tester.pumpWidget(
      _harness(
        reduceMotion: true,
        exercise: const ExerciseDetail(
          exerciseId: 1,
          name: '3/4 sit-up',
          muscleGroup: 'abs',
          equipment: 'body weight',
          thumbnailUrl: null,
          animationUrl: _gif,
          cues: [],
        ),
      ),
    );
    await tester.pump();

    expect(_imageOf(_gif), findsOneWidget);
    expect(_ticking(tester, _imageOf(_gif)), isFalse);
    expect(find.bySemanticsLabel('Play demo'), findsOneWidget);
  });

  testWidgets('without an animation, no demo or control is shown', (
    tester,
  ) async {
    _useSurface(tester, const Size(390, 844));
    await tester.pumpWidget(
      _harness(
        exercise: const ExerciseDetail(
          exerciseId: 1,
          name: '3/4 sit-up',
          muscleGroup: 'abs',
          equipment: 'body weight',
          thumbnailUrl: _thumb,
          animationUrl: null,
          cues: [],
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(find.bySemanticsLabel('Play demo'), findsNothing);
    expect(find.bySemanticsLabel('Pause demo'), findsNothing);
  });

  testWidgets('an unreachable animation falls back to the equipment icon', (
    tester,
  ) async {
    _useSurface(tester, const Size(390, 844));
    await tester.pumpWidget(_harness());
    // Let the test HTTP client refuse both requests.
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.accessibility_new), findsWidgets);
  });

  testWidgets('fits a 320 dp screen at 2x text', (tester) async {
    _useSurface(tester, const Size(320, 640));
    await tester.pumpWidget(_harness(textScale: 2));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tester.getRect(_imageOf(_gif)).right, lessThanOrEqualTo(320));
  });
}
