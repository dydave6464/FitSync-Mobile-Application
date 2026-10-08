import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/exercises/domain/exercise_cues.dart';
import 'package:fitsync/features/exercises/presentation/widgets/coach_panel.dart';

const _ai = ExerciseCues(
  source: 'ai',
  injuryName: 'Knee',
  cues: [
    Cue(
      title: 'Keep the front knee over the toes',
      detail: 'Stop short of pain.',
    ),
    Cue(title: 'Lower slowly', detail: 'Three seconds down.'),
  ],
);
final _catalogue = ExerciseCues.catalogue(['Stand tall.', 'Step back.']);

Future<void> _pump(
  WidgetTester tester,
  AsyncValue<ExerciseCues> cues, {
  VoidCallback? onRetry,
  bool reduceMotion = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(
          body: SingleChildScrollView(
            child: CoachPanel(
              injuryName: 'Knee',
              cues: cues,
              catalogue: _catalogue,
              onRetry: onRetry ?? () {},
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  test('notice is read from the response', () {
    final cues = ExerciseCues.fromJson({
      'source': 'catalogue',
      'injury': {'injuryId': 3, 'name': 'Knee', 'reason': 'trains_region'},
      'notice': 'free_limit',
      'cues': [
        {'title': 'Stand tall.'},
      ],
    });
    expect(cues.notice, 'free_limit');
    expect(ExerciseCues.fromJson({'source': 'ai', 'cues': []}).notice, isNull);
  });

  testWidgets('while loading it says the cues are being written', (
    tester,
  ) async {
    await _pump(tester, const AsyncValue.loading());
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('coach.loading')), findsOneWidget);
    expect(find.text('Writing cues for your knee…'), findsOneWidget);
    // The catalogue steps are not shown first and then swapped.
    expect(find.text('Stand tall.'), findsNothing);
  });

  testWidgets('AI cues sit in the coach panel with its header', (tester) async {
    await _pump(tester, const AsyncValue.data(_ai));
    await tester.pumpAndSettle();
    final panel = find.byKey(const Key('coach.panel'));
    expect(panel, findsOneWidget);
    Finder inPanel(String s) =>
        find.descendant(of: panel, matching: find.text(s));
    expect(inPanel('AI coaching for your knee'), findsOneWidget);
    expect(inPanel('Written for your knee injury.'), findsOneWidget);
    expect(inPanel('Guidance, not medical advice.'), findsOneWidget);
    expect(inPanel('Keep the front knee over the toes'), findsOneWidget);
    expect(inPanel('Lower slowly'), findsOneWidget);
  });

  Finder firstCardFade() => find
      .ancestor(
        of: find.text('Keep the front knee over the toes'),
        matching: find.byType(FadeTransition),
      )
      .first;

  testWidgets('the cards slide in across time', (tester) async {
    await _pump(tester, const AsyncValue.data(_ai));

    // Immediately after the first frame the controller has not advanced at
    // all, so the opacity would trivially read 0 and prove nothing about an
    // animation in progress. Pumping partway through it is what shows the
    // card genuinely mid-transition rather than merely not-yet-started.
    await tester.pump(const Duration(milliseconds: 100));
    final mid = tester.widget<FadeTransition>(firstCardFade());
    expect(mid.opacity.value, greaterThan(0.0), reason: 'animating in');
    expect(mid.opacity.value, lessThan(1.0), reason: 'animating in');

    await tester.pumpAndSettle();
    final settled = tester.widget<FadeTransition>(firstCardFade());
    expect(settled.opacity.value, 1.0);
  });

  testWidgets('reduce motion shows the cards at once, with no animation', (
    tester,
  ) async {
    await _pump(tester, const AsyncValue.data(_ai), reduceMotion: true);

    final still = tester.widget<FadeTransition>(firstCardFade());
    expect(still.opacity.value, 1.0);
  });

  testWidgets('a failed request shows the standard steps and Try again', (
    tester,
  ) async {
    var retried = 0;
    await _pump(
      tester,
      AsyncValue.error(Exception('down'), StackTrace.empty),
      onRetry: () => retried++,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('coach.unavailable')), findsOneWidget);
    expect(
      find.text(
        "Couldn't write knee cues right now. Here are the standard steps.",
      ),
      findsOneWidget,
    );
    expect(find.text('Stand tall.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('coach.retry')));
    expect(retried, 1);
  });

  testWidgets('an unavailable notice shows the same fallback', (tester) async {
    final unavailable = ExerciseCues.fromJson({
      'source': 'catalogue',
      'injury': {'injuryId': 3, 'name': 'Knee'},
      'notice': 'unavailable',
      'cues': [
        {'title': 'Stand tall.'},
      ],
    });
    await _pump(tester, AsyncValue.data(unavailable));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('coach.unavailable')), findsOneWidget);
    expect(find.byKey(const Key('coach.retry')), findsOneWidget);
  });

  testWidgets('the free limit explains itself and offers no retry', (
    tester,
  ) async {
    final limited = ExerciseCues.fromJson({
      'source': 'catalogue',
      'injury': {'injuryId': 3, 'name': 'Knee'},
      'notice': 'free_limit',
      'cues': [
        {'title': 'Stand tall.'},
      ],
    });
    await _pump(tester, AsyncValue.data(limited));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('coach.freeLimit')), findsOneWidget);
    expect(
      find.text(
        "You've used today's free AI coaching. Here are the standard steps. "
        'Pro gives AI coaching on every exercise.',
      ),
      findsOneWidget,
    );
    expect(find.text('Stand tall.'), findsOneWidget);
    expect(find.byKey(const Key('coach.retry')), findsNothing);
  });

  testWidgets('catalogue cues with no notice render as the plain steps', (
    tester,
  ) async {
    await _pump(tester, AsyncValue.data(_catalogue));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('coach.panel')), findsNothing);
    expect(find.text('How to perform'), findsOneWidget);
  });
}
