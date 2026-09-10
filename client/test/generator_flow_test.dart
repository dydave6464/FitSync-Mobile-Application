import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fitsync/core/api_client.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/features/exercises/presentation/providers.dart' show apiClientProvider;
import 'package:fitsync/features/plans/data/plan_repository.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/plans/presentation/generator_screen.dart';
import 'package:fitsync/features/plans/presentation/plan_screen.dart';
import 'package:fitsync/features/plans/presentation/providers.dart';
import 'package:fitsync/features/sessions/domain/active_session.dart';
import 'package:fitsync/features/sessions/presentation/providers.dart';

const _fullBody = WorkoutPlan(
  planId: 1, name: 'Week 1 — Full body', splitStyle: 'full_body',
  daysPerWeek: 3, sessionLengthMin: 45, weekNo: 1,
  days: [PlanDay(dayNo: 1, name: 'Full body')],
  exercises: [
    PlanExercise(
      planExerciseId: 1, exerciseId: 11, name: 'Goblet squat',
      muscleGroup: 'quads', dayNo: 1, orderNo: 1, targetSets: 3, targetReps: '8-12',
    ),
  ],
);

const _ppl = WorkoutPlan(
  planId: 2, name: 'Week 1 — Push/Pull/Legs', splitStyle: 'push_pull_legs',
  daysPerWeek: 4, sessionLengthMin: 60, weekNo: 1,
  days: [
    PlanDay(dayNo: 1, name: 'Push'),
    PlanDay(dayNo: 2, name: 'Pull'),
    PlanDay(dayNo: 3, name: 'Legs'),
  ],
  exercises: [
    PlanExercise(
      planExerciseId: 2, exerciseId: 22, name: 'Bench press',
      muscleGroup: 'pectorals', dayNo: 1, orderNo: 1, targetSets: 3, targetReps: '8-12',
    ),
  ],
);

/// No session in progress -- this test drives Generate, not Start/Resume.
class _NoSessionController extends ActiveSessionController {
  @override
  Future<ActiveSession?> build() async => null;
}

/// Keeps anything downstream of the API client off the platform channel.
ApiClient _hermeticClient() => ApiClient(
      baseUrl: 'http://test.local',
      tokens: TokenStore(backing: InMemorySecureStore()),
      client: MockClient((_) async => http.Response('{"data":{}}', 200)),
    );

/// A small fake that only stubs `regenerate` -- a `noSuchMethod` fallthrough
/// covers the rest, so this test does not have to fake methods it never
/// calls.
class FlowRepository implements PlanRepository {
  FlowRepository({required this.onRegenerate});

  final VoidCallback onRegenerate;

  @override
  String get baseUrl => 'http://test.local';

  @override
  Future<WorkoutPlan> regenerate({
    required String splitStyle,
    required int daysPerWeek,
    required int sessionLengthMin,
  }) async {
    onRegenerate();
    return _ppl;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used by this test');
}

void main() {
  testWidgets('generating push/pull/legs makes the plan tab name the day',
      (tester) async {
    // The plan the provider hands back changes once regenerate has run, the
    // way the server's would.
    var generated = false;
    final repo = FlowRepository(onRegenerate: () => generated = true);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(_hermeticClient()),
          activePlanProvider.overrideWith((ref) async => generated ? _ppl : _fullBody),
          activeSessionProvider.overrideWith(() => _NoSessionController()),
          completedDaysProvider.overrideWith((ref) async => const <String>{}),
          planRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          theme: fsLightTheme(),
          home: const PlanScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // A one-day rotation is deliberately unlabelled, so before the generate
    // nothing on this screen names a day at all.
    expect(find.text('Push'), findsNothing);

    // Pushed onto the SAME navigator, so the pop after a successful generate
    // returns to this Plan tab rather than to an empty route.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(MaterialPageRoute<void>(builder: (_) => const GeneratorScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Push / Pull / Legs'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('gen.generate')));
    await tester.pumpAndSettle();

    expect(generated, isTrue, reason: 'the generate must reach the repository');
    expect(
      find.text('Push'),
      findsOneWidget,
      reason: 'the plan tab must re-read and name the new rotation day',
    );
  });
}
