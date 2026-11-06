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

/// True when [finder]'s paragraph is shown whole: not ellipsized or clipped
/// at its line limit.
bool _whole(WidgetTester tester, Finder finder) =>
    !tester.renderObject<RenderParagraph>(finder).didExceedMaxLines;

void main() {
  setUpAll(() async {
    await _load('SpaceGrotesk', 'assets/fonts/SpaceGrotesk-Variable.ttf');
    await _load('JetBrainsMono', 'assets/fonts/JetBrainsMono-Variable.ttf');
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
      expect(_whole(tester, label), isTrue);
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
