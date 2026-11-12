import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/onboarding/presentation/edit_scaffold.dart';

/// Pushes [editor] over a launcher screen, the way Settings opens one.
Future<void> _open(
  WidgetTester tester,
  Widget editor, {
  bool settle = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: fsLightTheme(),
      home: Builder(
        builder: (c) => TextButton(
          onPressed: () =>
              Navigator.of(c)
                  .push(MaterialPageRoute<void>(builder: (_) => editor)),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }
}

void main() {
  testWidgets('back on a dirty editor asks first', (tester) async {
    await _open(
      tester,
      EditScaffold(
        title: 'Height',
        dirty: true,
        onSave: () {},
        child: const Text('body'),
      ),
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Discard your changes?'), findsOneWidget);

    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('body'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('body'), findsNothing);
  });

  testWidgets('the app bar back on a dirty editor asks too', (tester) async {
    await _open(
      tester,
      EditScaffold(
        title: 'Height',
        dirty: true,
        onSave: () {},
        child: const Text('body'),
      ),
    );

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Discard your changes?'), findsOneWidget);
  });

  testWidgets('a clean editor pops without asking, and shows its error above '
      'Save', (tester) async {
    await _open(
      tester,
      EditScaffold(
        title: 'Height',
        onSave: () {},
        error: 'Height must be 100-250 cm',
        child: const Text('body'),
      ),
    );

    final error = find.text('Height must be 100-250 cm');
    expect(
      find.ancestor(of: error, matching: find.byType(FsErrorLine)),
      findsOneWidget,
    );
    // Directly above Save: its bottom edge sits on Save's top edge, give or
    // take the gap, so it is in view whenever Save is.
    final errorRect = tester.getRect(
      find.ancestor(of: error, matching: find.byType(FsErrorLine)),
    );
    final saveRect = tester.getRect(find.byKey(const Key('save')));
    expect(errorRect.bottom, lessThanOrEqualTo(saveRect.top));
    expect(saveRect.top - errorRect.bottom, lessThan(24));

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Discard your changes?'), findsNothing);
    expect(find.text('body'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('no error, no error line', (tester) async {
    await _open(
      tester,
      EditScaffold(title: 'Height', onSave: () {}, child: const Text('body')),
    );
    expect(find.byType(FsErrorLine), findsNothing);
  });

  testWidgets('a save in flight does not ask on back', (tester) async {
    // Save's spinner never settles, so frames are pumped by hand.
    await _open(
      tester,
      EditScaffold(
        title: 'Height',
        dirty: true,
        busy: true,
        onSave: () {},
        child: const Text('body'),
      ),
      settle: false,
    );

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Discard your changes?'), findsNothing);
    expect(find.text('body'), findsNothing);
  });
}
