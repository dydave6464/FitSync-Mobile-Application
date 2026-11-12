import 'dart:io';
import 'dart:typed_data' show ByteData;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/units.dart';
import 'package:fitsync/features/profile/presentation/providers.dart'
    show weightUnitProvider;
import 'package:fitsync/features/recovery/domain/recovery.dart';
import 'package:fitsync/features/recovery/presentation/providers.dart';
import 'package:fitsync/features/recovery/presentation/recovery_screen.dart';

/// The real face, not the test harness's, which draws every glyph a full
/// em wide: the check-in row's switch point was measured in Space Grotesk,
/// so only Space Grotesk can say whether it holds. Kept in its own file so
/// the rest of the Recovery tests keep the harness font.
Future<void> _loadFont() async {
  final bytes = await File('assets/fonts/SpaceGrotesk-Variable.ttf')
      .readAsBytes();
  await (FontLoader(
    'SpaceGrotesk',
  )..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
}

/// No check-in today, so the button says "Check in", the longer of its two
/// labels.
const _noCheckinToday = RecoveryOverview(
  todayCheckin: null,
  latestEstimate: InjuryRiskEstimate(
    riskLevel: 'moderate',
    trainingLoadScore: 47.25,
    checkinDate: '2026-10-15',
    source: 'rules',
    drivers: [RiskDriver(key: 'sleep', value: 'poor')],
  ),
  load: [],
);

/// Every group the server names, never trained and trained, so each row
/// carries the longest "when" there is.
const _muscles = RecoveryOverview(
  todayCheckin: null,
  latestEstimate: null,
  load: [],
  muscles: [
    MuscleRecency(group: 'shoulders', lastTrained: null, daysAgo: null),
    MuscleRecency(group: 'chest', lastTrained: '2026-10-01', daysAgo: 14),
    MuscleRecency(group: 'legs', lastTrained: null, daysAgo: null),
  ],
);

/// How many lines [text] was laid out on.
int _lines(WidgetTester tester, String text) {
  final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.length),
  );
  return boxes.map((b) => b.top.round()).toSet().length;
}

Future<void> _pump(
  WidgetTester tester,
  double width,
  double textScale, {
  RecoveryOverview overview = _noCheckinToday,
  String scrollTo = 'recovery.checkin',
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        recoveryOverviewProvider.overrideWith((ref) async => overview),
        weightUnitProvider.overrideWithValue(WeightUnit.kg),
      ],
      child: MaterialApp(
        theme: fsLightTheme(),
        home: const Scaffold(body: RecoveryScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.byKey(Key(scrollTo)), 200);
  await tester.pumpAndSettle();
}

/// Whether the button sits under the "Morning check-in" line rather than
/// beside it.
bool _under(WidgetTester tester) =>
    tester.getTopLeft(find.byKey(const Key('recovery.checkin'))).dy >=
    tester.getBottomLeft(find.text('Morning check-in')).dy;

void main() {
  setUpAll(_loadFont);

  testWidgets('on a common phone the check-in button sits beside its line', (
    tester,
  ) async {
    await _pump(tester, 390, 1);
    expect(tester.takeException(), isNull);
    expect(_under(tester), isFalse);
  });

  testWidgets('on a small phone at 2x text it moves under its line', (
    tester,
  ) async {
    await _pump(tester, 320, 2);
    expect(tester.takeException(), isNull);
    expect(_under(tester), isTrue);
  });

  testWidgets('at the largest iOS text it still fits a small phone', (
    tester,
  ) async {
    // iOS's accessibility sizes reach about 3.1x body text.
    await _pump(tester, 320, 3.2);
    expect(tester.takeException(), isNull);
  });

  group('last trained', () {
    testWidgets('at 2x text the group name is never split mid-word', (
      tester,
    ) async {
      await _pump(
        tester,
        360,
        2,
        overview: _muscles,
        scrollTo: 'recovery.muscles',
      );
      expect(tester.takeException(), isNull);
      expect(_lines(tester, 'Shoulders'), 1);
    });

    testWidgets('at the largest iOS text a small phone does not overflow', (
      tester,
    ) async {
      await _pump(
        tester,
        320,
        3.2,
        overview: _muscles,
        scrollTo: 'recovery.muscles',
      );
      expect(tester.takeException(), isNull);
      expect(_lines(tester, 'Shoulders'), 1);
    });
  });
}
