import 'dart:io';
import 'dart:typed_data' show ByteData;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/pro/presentation/providers.dart';
import 'package:fitsync/features/profile/domain/body_weight.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';
import 'package:fitsync/features/sessions/domain/session_history.dart';
import 'package:fitsync/features/sessions/domain/share_preview.dart';
import 'package:fitsync/features/sessions/domain/training_analytics.dart';
import 'package:fitsync/features/sessions/domain/volume_labels.dart';
import 'package:fitsync/features/sessions/presentation/providers.dart';
import 'package:fitsync/features/sessions/presentation/widgets/share_report_sheet.dart';

import 'helpers/fake_pro_repository.dart';

/// The real faces, not the test harness's: whether the preview's heading
/// fits its lines at 2x on a 320 dp phone depends on JetBrains Mono's widths,
/// and the harness font is wider. Kept in its own file so the sheet's other
/// tests keep the harness font.
Future<void> _load(String family, String path) async {
  final bytes = await File(path).readAsBytes();
  await (FontLoader(
    family,
  )..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
}

class _StubProfileNotifier extends ProfileNotifier {
  @override
  Future<Profile> build() async => const Profile(
    userId: 7,
    email: 'juan@example.com',
    fullName: 'Juan Dela Cruz',
    onboardingCompleted: true,
    isPremium: true,
    notificationsEnabled: true,
    equipment: [],
    injuries: [],
  );
}

void main() {
  setUpAll(() async {
    await _load('SpaceGrotesk', 'assets/fonts/SpaceGrotesk-Variable.ttf');
    await _load('JetBrainsMono', 'assets/fonts/JetBrainsMono-Variable.ttf');
  });

  // A year window crosses a year boundary, so it carries both years:
  // "YEAR · NOV 10, 2025 – NOV 9, 2026" takes three lines at 2.0x on 320 dp.
  testWidgets('a year heading shows whole at 2.0x on a 320 dp phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          proRepositoryProvider.overrideWithValue(FakeProRepository()),
          profileProvider.overrideWith(_StubProfileNotifier.new),
          trainingSummaryProvider.overrideWith(
            (ref) async => const TrainingSummary(
              sessionCount: 13,
              setCount: 75,
              totalVolumeKg: 31243.5,
            ),
          ),
          trainingAnalyticsProvider('year').overrideWith(
            (ref) async => const TrainingAnalytics(
              period: 'year',
              volume: [],
              change: VolumeChange(
                totalKg: 31243.5,
                previousKg: 25800,
                changePct: 21,
              ),
              adherence: Adherence(done: 13, target: 13, weeks: 52),
              muscles: [],
            ),
          ),
          bodyWeightProvider('year').overrideWith(
            (ref) async => const BodyWeightSeries(
              widened: false,
              points: [
                BodyWeightPoint(loggedOn: '2026-01-16', weightKg: 78.4),
                BodyWeightPoint(loggedOn: '2026-11-06', weightKg: 75.2),
              ],
              reference: null,
              unit: 'kg',
            ),
          ),
        ],
        child: MaterialApp(
          theme: fsLightTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showShareReportSheet(context, period: 'year'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final heading = 'Year · ${shareWindowLabel('year', volumeToday())}'
        .toUpperCase();
    final paragraph = tester.renderObject<RenderParagraph>(find.text(heading));
    expect(paragraph.didExceedMaxLines, isFalse, reason: heading);
    expect(tester.takeException(), isNull);
  });
}
