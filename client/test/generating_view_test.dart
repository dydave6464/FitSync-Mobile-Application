import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/onboarding/presentation/generating_view.dart';

Widget _host(Widget child) => MaterialApp(home: child);

/// The onboarding wording, which is what every test below that does not say
/// otherwise is about.
Future<void> _pump(
  WidgetTester tester, {
  bool saved = false,
  bool planReady = false,
  List<String> avoiding = const [],
}) => tester.pumpWidget(
  _host(
    GeneratingView(
      title: 'Building your plan…',
      subtitle:
          'Matching exercises to your goals, equipment, '
          'and injury history.',
      leadLabel: 'Profile saved',
      leadDone: saved,
      planReady: planReady,
      avoiding: avoiding,
    ),
  ),
);

/// Tears the view down so its reveal timers are cancelled. A widget test fails
/// if a timer is still pending when it ends.
Future<void> _close(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox.shrink());

/// Just past the slot each row is allowed to tick in.
Duration _justAfter(int row) =>
    GeneratingPace.onboarding.revealAt[row] + const Duration(milliseconds: 100);

void main() {
  testWidgets('says what it is doing', (tester) async {
    await _pump(tester);

    expect(find.text('Building your plan…'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('names the injuries it is working around', (tester) async {
    await _pump(tester, saved: true, avoiding: ['Lower back', 'Right knee']);

    // The mockup hardcodes "Avoiding lower-back load". Reading the user's own
    // reported injuries back to them is the whole point of the row — a
    // regression to fixed copy would pass a findsOneWidget on any text.
    expect(find.text('Avoiding Lower back, Right knee'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('still has an injury row to tick when nothing was reported', (
    tester,
  ) async {
    await _pump(tester, saved: true);

    // A healthy user watched a two-row list where everyone else saw three.
    // The row says what is true for them instead of being dropped.
    expect(find.text('No injuries to work around'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('ticks its rows one at a time, not all at once', (tester) async {
    await _pump(tester, saved: true, planReady: true, avoiding: ['Lower back']);

    // Everything this screen reports is already done — but firing three ticks
    // in the same frame reads as a flicker, not as progress.
    expect(find.byKey(const Key('gen.lead.done')), findsNothing);

    await tester.pump(_justAfter(0));
    expect(find.byKey(const Key('gen.lead.done')), findsOneWidget);
    expect(find.byKey(const Key('gen.avoiding.done')), findsNothing);

    await tester.pump(_justAfter(1) - _justAfter(0));
    expect(find.byKey(const Key('gen.avoiding.done')), findsOneWidget);
    expect(find.byKey(const Key('gen.exercises.done')), findsNothing);

    await tester.pump(_justAfter(2) - _justAfter(1));
    expect(find.byKey(const Key('gen.exercises.done')), findsOneWidget);
    await _close(tester);
  });

  testWidgets(
    'a row still waits for its work, however long its slot has passed',
    (tester) async {
      await _pump(
        tester,
        saved: false,
        planReady: false,
        avoiding: ['Lower back'],
      );

      await tester.pump(GeneratingPace.onboarding.minimumRun * 2);

      // The pacing decides how early a tick may appear, never whether it is
      // earned. Ticking on a timer alone would be the prototype's fiction.
      expect(find.byKey(const Key('gen.lead.done')), findsNothing);
      expect(find.byKey(const Key('gen.avoiding.done')), findsNothing);
      expect(find.byKey(const Key('gen.exercises.done')), findsNothing);
      await _close(tester);
    },
  );

  testWidgets('the exercises row waits for the plan, not just for its slot', (
    tester,
  ) async {
    await _pump(tester, saved: true, planReady: false);

    await tester.pump(_justAfter(2));

    expect(find.byKey(const Key('gen.lead.done')), findsOneWidget);
    expect(
      find.byKey(const Key('gen.exercises.done')),
      findsNothing,
      reason: 'this row is the work still running; ticking it would be a lie',
    );
    await _close(tester);
  });

  testWidgets('refuses to pop, so back cannot abandon a half-written profile', (
    tester,
  ) async {
    await _pump(tester, saved: true);

    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
    await _close(tester);
  });

  testWidgets('stays up long enough to be read', (tester) async {
    // The whole round trip can finish in under a second. Six to seven seconds
    // is the floor the screen is built around: the last row cannot tick before
    // 5.5s, and it is held afterwards so its tick is seen.
    expect(
      GeneratingPace.onboarding.minimumRun.inMilliseconds,
      greaterThanOrEqualTo(6000),
    );
    expect(
      GeneratingPace.onboarding.minimumRun,
      GeneratingPace.onboarding.revealAt.last + GeneratingPace.onboarding.tail,
    );
  });

  testWidgets('the regenerate pace is roughly half the onboarding pace', (
    tester,
  ) async {
    // Onboarding happens once and the wait is the product introducing itself.
    // Regenerating is something a user does repeatedly while tuning a split,
    // where seven seconds every time grates.
    expect(
      GeneratingPace.regenerate.minimumRun.inMilliseconds,
      lessThan(GeneratingPace.onboarding.minimumRun.inMilliseconds),
    );
    expect(
      GeneratingPace.regenerate.minimumRun,
      GeneratingPace.regenerate.revealAt.last + GeneratingPace.regenerate.tail,
    );
    expect(GeneratingPace.regenerate.revealAt, hasLength(3));
  });

  testWidgets('the lead row states the split and the schedule', (tester) async {
    await tester.pumpWidget(
      _host(
        const GeneratingView(
          title: 'Rebuilding your plan…',
          subtitle:
              'Matching exercises to your split, your equipment, '
              'and your injuries.',
          leadLabel: 'Push / Pull / Legs, Mon · Wed · Fri',
          leadDone: true,
          avoiding: [],
          planReady: false,
          pace: GeneratingPace.regenerate,
        ),
      ),
    );

    expect(find.text('Rebuilding your plan…'), findsOneWidget);
    expect(find.text('Push / Pull / Legs, Mon · Wed · Fri'), findsOneWidget);
    expect(find.text('No injuries to work around'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('the injury row keeps both its states', (tester) async {
    // Row 2 is always the injury row, with its own two states. It is not a
    // fallback for anything the lead row says.
    await tester.pumpWidget(
      _host(
        const GeneratingView(
          title: 'Rebuilding your plan…',
          subtitle: 'x',
          leadLabel: 'Full body, 3 days a week',
          leadDone: true,
          avoiding: ['Knee (right)'],
          planReady: false,
          pace: GeneratingPace.regenerate,
        ),
      ),
    );

    expect(find.text('Avoiding Knee (right)'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('the regenerate pace paces its own rows, and still gates them', (
    tester,
  ) async {
    // The gates move with the pace; what they gate does not. The exercises row
    // is the one piece of work still running here, and it stays untucked
    // however far past its slot the screen has run.
    await tester.pumpWidget(
      _host(
        const GeneratingView(
          title: 'Rebuilding your plan…',
          subtitle: 'x',
          leadLabel: 'Full body, 3 days a week',
          leadDone: true,
          avoiding: [],
          planReady: false,
          pace: GeneratingPace.regenerate,
        ),
      ),
    );

    expect(find.byKey(const Key('gen.lead.done')), findsNothing);

    await tester.pump(
      GeneratingPace.regenerate.revealAt[0] + const Duration(milliseconds: 100),
    );
    expect(find.byKey(const Key('gen.lead.done')), findsOneWidget);
    expect(
      find.byKey(const Key('gen.avoiding.done')),
      findsNothing,
      reason: 'the onboarding slots would still be shut at 0.9s',
    );

    await tester.pump(GeneratingPace.regenerate.minimumRun * 2);
    expect(
      find.byKey(const Key('gen.exercises.done')),
      findsNothing,
      reason: 'pacing, never progress: the plan has not come back',
    );
    await _close(tester);
  });

  testWidgets('a poppable generating screen is opt-in', (tester) async {
    // Onboarding cannot be backed out of; regenerating can, and nothing is
    // half-written while it runs. The default is the stricter one.
    await tester.pumpWidget(
      _host(
        const GeneratingView(
          title: 'Rebuilding your plan…',
          subtitle: 'x',
          leadLabel: 'Full body, 3 days a week',
          leadDone: true,
          avoiding: [],
          planReady: false,
          pace: GeneratingPace.regenerate,
          canPop: true,
        ),
      ),
    );

    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isTrue);
    await _close(tester);
  });
}
