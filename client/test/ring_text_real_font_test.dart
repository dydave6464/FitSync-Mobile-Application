import 'dart:io';
import 'dart:typed_data' show ByteData;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_charts.dart' show FsRing;
import 'package:fitsync/features/home/presentation/widgets/readiness_card.dart';
import 'package:fitsync/features/recovery/domain/recovery.dart';
import 'package:fitsync/features/routine/data/routine_repository.dart';
import 'package:fitsync/features/routine/domain/routine.dart';
import 'package:fitsync/features/routine/presentation/providers.dart';
import 'package:fitsync/features/routine/presentation/routine_screen.dart';

/// The real faces, not the test harness's: whether a ring's words clear its
/// stroke depends on how wide Space Grotesk draws them. Kept in its own file
/// so the rest of these screens' tests keep the harness font.
Future<void> _load(String family, String path) async {
  final bytes = await File(path).readAsBytes();
  await (FontLoader(
    family,
  )..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
}

/// The drawn words of [text], as global corners: where the glyphs land,
/// after any scaling, whatever box the Text widget was given.
List<Offset> _corners(WidgetTester tester, Finder text) {
  final paragraph = tester.renderObject<RenderParagraph>(text);
  final box = paragraph
      .getBoxesForSelection(
        TextSelection(
          baseOffset: 0,
          extentOffset: paragraph.text.toPlainText().length,
        ),
      )
      .map((b) => b.toRect())
      .reduce((a, b) => a.expandToInclude(b));
  return [
    box.topLeft,
    box.topRight,
    box.bottomLeft,
    box.bottomRight,
  ].map(paragraph.localToGlobal).toList();
}

/// Every corner of every [texts] inside [ring]'s clear middle: the circle
/// inside its stroke.
void _expectInside(WidgetTester tester, Finder ring, List<String> texts) {
  final r = tester.widget<FsRing>(ring);
  final centre = tester.getRect(ring).center;
  final clear = r.size / 2 - r.stroke;
  for (final words in texts) {
    final text = find.descendant(of: ring, matching: find.text(words));
    for (final corner in _corners(tester, text)) {
      final d = (corner - centre).distance;
      expect(
        d,
        lessThanOrEqualTo(clear),
        reason:
            '"$words" corner is ${d.toStringAsFixed(1)} dp from the centre; '
            'the clear middle ends at $clear',
      );
    }
  }
}

/// The font size [words] in [ring] is drawn at: its own size, times the
/// system text scale, times whatever its FittedBox shrank it by.
double _drawnSize(WidgetTester tester, Finder ring, String words) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: ring, matching: find.text(words)),
  );
  final fit =
      (paragraph.localToGlobal(const Offset(1, 0)) -
              paragraph.localToGlobal(Offset.zero))
          .dx;
  return paragraph.text.style!.fontSize! * paragraph.textScaler.scale(1) * fit;
}

class _Routine implements RoutineRepository {
  _Routine(this.day);
  final RoutineDay day;

  @override
  Future<RoutineDay> today() async => day;

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} is not used here');
}

/// A full day of [n] habits: "10/10" is the widest count with real fonts
/// (wider than "12/12"), "12/12" the most habits a day is likely to hold.
RoutineDay _allDone(int n) => RoutineDay(
  date: '2026-10-19',
  habits: [
    for (var i = 1; i <= n; i++)
      Habit(
        habitId: i,
        title: 'Habit $i',
        time: null,
        durationMin: null,
        weekdays: const [1, 2, 3, 4, 5, 6, 7],
        done: true,
      ),
  ],
  workout: null,
);

Future<void> _scaled(WidgetTester tester, double scale) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

void main() {
  setUpAll(() async {
    await _load('SpaceGrotesk', 'assets/fonts/SpaceGrotesk-Variable.ttf');
    await _load('JetBrainsMono', 'assets/fonts/JetBrainsMono-Variable.ttf');
  });

  for (final scale in [1.0, 1.3, 2.0]) {
    for (final n in [10, 12]) {
      testWidgets("the routine ring's $n/$n clears its stroke at ${scale}x", (
        tester,
      ) async {
        await _scaled(tester, scale);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              routineRepositoryProvider.overrideWithValue(
                _Routine(_allDone(n)),
              ),
            ],
            child: MaterialApp(
              theme: fsLightTheme(),
              home: const RoutineScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        _expectInside(tester, find.byType(FsRing), ['$n/$n']);
        // Fitting it in leaves normal text exactly as it was.
        if (scale == 1.0) {
          expect(
            _drawnSize(tester, find.byType(FsRing), '$n/$n'),
            closeTo(15, 0.05),
          );
        }
      });
    }

    for (final (name, score, texts) in [
      ('a full score', 0.0, ['100', 'READY']),
      ('no score', null, ['–']),
    ]) {
      testWidgets("the readiness ring's words clear its stroke with $name at "
          '${scale}x', (tester) async {
        await _scaled(tester, scale);
        await tester.pumpWidget(
          MaterialApp(
            theme: fsLightTheme(),
            home: Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  ReadinessCard(
                    estimate: InjuryRiskEstimate(
                      riskLevel: 'low',
                      trainingLoadScore: score,
                      checkinDate: '2026-10-19',
                    ),
                    todayCheckin: null,
                    onCheckIn: () {},
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        _expectInside(tester, find.byType(FsRing), texts);
        // At normal text the score and its label keep exactly their sizes.
        if (scale == 1.0 && score != null) {
          expect(
            _drawnSize(tester, find.byType(FsRing), '100'),
            closeTo(20, 0.05),
          );
          expect(
            _drawnSize(tester, find.byType(FsRing), 'READY'),
            closeTo(8.5, 0.05),
          );
        }
      });
    }
  }
}
