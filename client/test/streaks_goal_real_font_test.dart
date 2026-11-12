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
import 'package:fitsync/features/streaks/data/streaks_repository.dart';
import 'package:fitsync/features/streaks/domain/streaks.dart';
import 'package:fitsync/features/streaks/presentation/providers.dart';
import 'package:fitsync/features/streaks/presentation/streaks_screen.dart';

/// Where a goal's figure sits beside its bar depends on how wide the figure
/// is, and only the real face measures like a phone: the harness font draws
/// every glyph a full em wide, about twice SpaceGrotesk. Kept in its own file
/// so the rest of the streaks tests keep the harness font.
Future<void> _load(String family, String path) async {
  final bytes = await File(path).readAsBytes();
  await (FontLoader(
    family,
  )..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
}

DateTime _now() => DateTime.utc(2026, 9, 24, 4);

class _Goals implements GoalsRepository {
  _Goals(this.goals);

  final List<LiftGoal> goals;

  @override
  Future<List<LiftGoal>> list() async => goals;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  required double textScale,
  required double? bestKg,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        streakProvider.overrideWith(
          (ref) async =>
              const Streak(current: 0, best: 0, todayActive: false, week: []),
        ),
        goalsRepositoryProvider.overrideWithValue(
          _Goals([
            LiftGoal(
              goalId: 1,
              exerciseId: 3,
              exerciseName: 'Bench Press',
              targetKg: 100,
              bestKg: bestKg,
              reachedOn: null,
            ),
          ]),
        ),
        weightUnitProvider.overrideWithValue(WeightUnit.kg),
      ],
      child: MaterialApp(
        theme: fsLightTheme(),
        home: const StreaksScreen(now: _now),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.byKey(const Key('streaks.goal.1')), 200);
  await tester.pumpAndSettle();
}

/// Whether [text] was laid out on a single line.
bool _oneLine(WidgetTester tester, Finder text) {
  final para = tester.renderObject<RenderParagraph>(text);
  final single = TextPainter(
    text: para.text,
    textDirection: TextDirection.ltr,
    textScaler: para.textScaler,
  )..layout();
  final one = para.size.height == single.height;
  single.dispose();
  return one;
}

void main() {
  setUpAll(() async {
    await _load('SpaceGrotesk', 'assets/fonts/SpaceGrotesk-Variable.ttf');
  });

  const figures = [
    (null, 'Not logged yet · 0 / 100 kg'),
    (52.5, '52.5 / 100 kg'),
  ];
  const phones = [Size(360, 640), Size(320, 568)];

  // The design's row: a bar, then the figure on one line, flush with the
  // card's content edge (the card less its 13 dp padding).
  for (final size in phones) {
    for (final scale in [1.0, 1.3]) {
      for (final (best, figure) in figures) {
        testWidgets('at ${scale}x on ${size.width.toInt()} dp, "$figure" is '
            'one line and ends at the card edge', (tester) async {
          await _pump(tester, size: size, textScale: scale, bestKg: best);

          final text = find.text(figure);
          expect(_oneLine(tester, text), isTrue, reason: 'wrapped');
          final card = tester.getRect(find.byKey(const Key('streaks.goal.1')));
          expect(tester.getRect(text).right, closeTo(card.right - 13, 0.5));
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  // Above 1.3x the figure takes its own line over the bar.
  for (final size in phones) {
    for (final (best, figure) in figures) {
      testWidgets('at 2.0x on ${size.width.toInt()} dp, "$figure" fits '
          'inside its card', (tester) async {
        await _pump(tester, size: size, textScale: 2.0, bestKg: best);

        expect(tester.takeException(), isNull);
        final card = tester.getRect(find.byKey(const Key('streaks.goal.1')));
        final text = tester.getRect(find.text(figure));
        expect(text.left, greaterThanOrEqualTo(card.left + 13 - 0.5));
        expect(text.right, lessThanOrEqualTo(card.right - 13 + 0.5));
      });
    }
  }
}
