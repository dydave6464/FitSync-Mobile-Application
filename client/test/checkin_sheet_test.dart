import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/recovery/data/recovery_repository.dart';
import 'package:fitsync/features/recovery/domain/recovery.dart';
import 'package:fitsync/features/recovery/presentation/providers.dart';
import 'package:fitsync/features/recovery/presentation/widgets/checkin_sheet.dart';

class _FakeRepo implements RecoveryRepository {
  Map<String, String>? sent;
  Object? error;

  @override
  Future<InjuryRiskEstimate> checkIn(Map<String, String> answers) async {
    if (error != null) throw error!;
    sent = answers;
    return const InjuryRiskEstimate(
      riskLevel: 'moderate',
      trainingLoadScore: 40,
      checkinDate: '2026-09-20',
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} is not used here');
}

Future<_FakeRepo> _open(WidgetTester tester, {Object? error}) async {
  final repo = _FakeRepo()..error = error;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [recoveryRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: fsLightTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showCheckinSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('it asks all four questions', (tester) async {
    await _open(tester);

    expect(find.text('Sleep'), findsOneWidget);
    expect(find.text('Soreness'), findsOneWidget);
    expect(find.text('Energy'), findsOneWidget);
    expect(find.text('Stress'), findsOneWidget);
  });

  testWidgets('it posts the values the server stores', (tester) async {
    final repo = await _open(tester);

    await tester.tap(find.byKey(const Key('checkin.sleepQuality.poor')));
    await tester.tap(find.byKey(const Key('checkin.muscleSoreness.severe')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('checkin.save')));
    await tester.pumpAndSettle();

    // Column spellings, untouched.
    expect(repo.sent!['sleepQuality'], 'poor');
    expect(repo.sent!['muscleSoreness'], 'severe');
  });

  testWidgets('a failed save says so and does not claim it saved', (
    tester,
  ) async {
    await _open(tester, error: Exception('offline'));

    await tester.tap(find.byKey(const Key('checkin.save')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Something went wrong'), findsOneWidget);
    expect(find.byKey(const Key('checkin.save')), findsOneWidget);
  });
}
