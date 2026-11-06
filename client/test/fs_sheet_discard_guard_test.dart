import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';

/// A sheet whose contents are dirty while [dirty] says so, opened from a
/// button, the way the check-in and habit sheets are.
Future<void> _open(WidgetTester tester, {required bool dirty}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: fsLightTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: false,
              isScrollControlled: true,
              builder: (_) => FsSheetDiscardGuard(
                dirty: dirty,
                message: 'Your answers won\'t be saved.',
                child: const FsSheetHeightCap(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(top: 10, bottom: 12),
                        child: FsSheetHandle(key: Key('t.handle')),
                      ),
                      SizedBox(height: 200, child: Text('Sheet body')),
                    ],
                  ),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _swipeDown(WidgetTester tester) async {
  await tester.fling(find.text('Sheet body'), const Offset(0, 300), 1500);
  await tester.pumpAndSettle();
}

void main() {
  // P-19: the check-in and habit sheets each held their own copy of this
  // drag claim. One kit widget now does it for both.
  group('FsSheetDiscardGuard', () {
    testWidgets('a swipe down on a clean sheet just closes it', (tester) async {
      await _open(tester, dirty: false);

      await _swipeDown(tester);

      expect(find.text('Discard your changes?'), findsNothing);
      expect(find.text('Sheet body'), findsNothing);
    });

    testWidgets('a swipe down on a dirty sheet asks first', (tester) async {
      await _open(tester, dirty: true);

      await _swipeDown(tester);

      expect(find.text('Discard your changes?'), findsOneWidget);
      expect(find.text("Your answers won't be saved."), findsOneWidget);
      await tester.tap(find.byKey(const Key('discard.keep')));
      await tester.pumpAndSettle();
      expect(find.text('Sheet body'), findsOneWidget);

      await _swipeDown(tester);
      await tester.tap(find.byKey(const Key('discard.confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Sheet body'), findsNothing);
    });

    testWidgets('a short nudge on a dirty sheet neither asks nor closes', (
      tester,
    ) async {
      await _open(tester, dirty: true);

      await tester.drag(find.text('Sheet body'), const Offset(0, 20));
      await tester.pumpAndSettle();

      expect(find.text('Discard your changes?'), findsNothing);
      expect(find.text('Sheet body'), findsOneWidget);
    });

    testWidgets('back on a dirty sheet asks too', (tester) async {
      await _open(tester, dirty: true);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Discard your changes?'), findsOneWidget);
    });

    testWidgets('the claim offers a screen reader no scroll of its own', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _open(tester, dirty: true);

      SemanticsNode? n = tester.getSemantics(find.text('Sheet body'));
      while (n != null) {
        final data = n.getSemanticsData();
        expect(data.hasAction(SemanticsAction.scrollDown), isFalse);
        expect(data.hasAction(SemanticsAction.scrollUp), isFalse);
        n = n.parent;
      }
      semantics.dispose();
    });
  });

  // P-23: the check-in and How to read sheets each capped their height at
  // 0.9 of the screen with their own copy.
  testWidgets('FsSheetHeightCap keeps a tall sheet to 0.9 of the screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Align(
          alignment: Alignment.bottomCenter,
          child: FsSheetHeightCap(
            child: SizedBox(key: Key('tall'), height: 2000, width: 100),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byKey(const Key('tall'))).height, 640 * 0.9);
  });

  // Under the theme's drag handle, Material puts the content 48 dp down, so
  // a 0.9 cap on the content alone would let the sheet grow 48 dp past it,
  // up under the status bar. The cap is on the whole sheet either way.
  testWidgets('FsSheetHeightCap counts the theme handle in the 0.9', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: fsLightTheme(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => const FsSheetHeightCap(
                child: SizedBox(height: 2000, width: 100),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final sheet = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(Material),
    );
    expect(
      tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle,
      isTrue,
    );
    expect(tester.getSize(sheet.first).height, 640 * 0.9);
  });
}
