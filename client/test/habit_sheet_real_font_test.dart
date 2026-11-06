import 'dart:io';
import 'dart:typed_data' show ByteData;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/routine/data/routine_repository.dart';
import 'package:fitsync/features/routine/domain/routine.dart';
import 'package:fitsync/features/routine/presentation/providers.dart';
import 'package:fitsync/features/routine/presentation/widgets/habit_sheet.dart';

/// The real faces, not the test harness's: whether the time button's label
/// or the duration placeholder is cut off depends on Space Grotesk's widths.
/// Kept in its own file so the other habit-sheet tests keep the harness font.
Future<void> _load(String family, String path) async {
  final bytes = await File(path).readAsBytes();
  await (FontLoader(
    family,
  )..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
}

class _NoopRepo implements RoutineRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

const _sevenAm = Habit(
  habitId: 7,
  title: 'Run',
  time: '07:00',
  durationMin: 20,
  weekdays: [1, 3],
  done: false,
);

Future<void> _open(
  WidgetTester tester, {
  Habit? existing,
  required double scale,
}) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [routineRepositoryProvider.overrideWithValue(_NoopRepo())],
      child: MediaQuery(
        data: MediaQueryData(
          size: const Size(360, 640),
          textScaler: TextScaler.linear(scale),
        ),
        child: MaterialApp(
          theme: fsLightTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showHabitSheet(context, existing: existing),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// True when [finder]'s paragraph is shown whole inside [holder].
///
/// The time button's label wraps, so it has no line limit to exceed and
/// `didExceedMaxLines` alone can never fail. Whole also means no word is
/// wider than the paragraph -- a word that is gets broken mid-word or runs
/// off -- and the paragraph lies inside the button rather than past its edge.
bool _whole(WidgetTester tester, Finder finder, Finder holder) {
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  if (paragraph.didExceedMaxLines) return false;
  final widestWord = paragraph.getMinIntrinsicWidth(double.infinity);
  if (widestWord > paragraph.size.width + 0.5) return false;
  final inside = tester.getRect(holder).inflate(0.5);
  final drawn = tester.getRect(finder);
  return inside.contains(drawn.topLeft) && inside.contains(drawn.bottomRight);
}

void main() {
  setUpAll(() async {
    await _load('SpaceGrotesk', 'assets/fonts/SpaceGrotesk-Variable.ttf');
    await _load('JetBrainsMono', 'assets/fonts/JetBrainsMono-Variable.ttf');
  });

  testWidgets('the check fails for a label too narrow to hold a word (L-42)', (
    tester,
  ) async {
    // Guards the guard: a time squeezed into 30 dp breaks "7:00" mid-word,
    // which the check must call cut off even though nothing exceeds a
    // line limit.
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            key: Key('narrow'),
            width: 30,
            child: Text('7:00 AM', style: TextStyle(fontSize: 13.5)),
          ),
        ),
      ),
    );

    expect(
      _whole(tester, find.text('7:00 AM'), find.byKey(const Key('narrow'))),
      isFalse,
    );
  });

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('the habit time shows whole, AM/PM included, at ${scale}x', (
      tester,
    ) async {
      await _open(tester, existing: _sevenAm, scale: scale);

      final label = find.descendant(
        of: find.byKey(const Key('habit.time')),
        matching: find.text('7:00 AM'),
      );
      expect(label, findsOneWidget);
      expect(
        _whole(tester, label, find.byKey(const Key('habit.time'))),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a new habit shows no cut-off placeholder in the duration '
        'field at ${scale}x', (tester) async {
      await _open(tester, scale: scale);

      final duration = find.byKey(const Key('habit.duration'));
      final texts = find.descendant(of: duration, matching: find.byType(Text));
      for (final element in texts.evaluate()) {
        final paragraph = find.descendant(
          of: find.byWidget(element.widget),
          matching: find.byType(RichText),
        );
        for (final p in paragraph.evaluate()) {
          final render = p.renderObject! as RenderParagraph;
          expect(
            render.didExceedMaxLines,
            isFalse,
            reason: '"${render.text.toPlainText()}" is cut off',
          );
        }
      }
      expect(tester.takeException(), isNull);
    });
  }
}
