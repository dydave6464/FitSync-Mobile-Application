import 'package:fitsync/features/auth/presentation/editable_under.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('finds the text field inside the keyed subtree', (tester) async {
    final outer = GlobalKey();
    final inner = TextEditingController(text: 'second');
    addTearDown(inner.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const TextField(),
              Padding(
                key: outer,
                padding: const EdgeInsets.all(8),
                child: TextField(controller: inner),
              ),
            ],
          ),
        ),
      ),
    );

    final editable = editableUnder(outer);
    expect(editable, isNotNull);
    expect(editable!.widget.controller, same(inner));
  });

  testWidgets('returns null when nothing editable is under the key', (
    tester,
  ) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Text('no field', key: key)),
      ),
    );
    expect(editableUnder(key), isNull);
  });

  test('returns null when the key is not mounted', () {
    expect(editableUnder(GlobalKey()), isNull);
  });

  group('focusOrAnnounce', () {
    Future<(GlobalKey, GlobalKey, BuildContext)> pump(
      WidgetTester tester,
    ) async {
      final first = GlobalKey();
      final second = GlobalKey();
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) {
                context = c;
                return Column(
                  children: [
                    Padding(
                      key: first,
                      padding: EdgeInsets.zero,
                      child: const TextField(key: Key('first')),
                    ),
                    Padding(
                      key: second,
                      padding: EdgeInsets.zero,
                      child: const TextField(key: Key('second')),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      return (first, second, context);
    }

    bool focused(WidgetTester tester, String key) => tester
        .widget<EditableText>(
          find.descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(EditableText),
          ),
        )
        .focusNode
        .hasFocus;

    testWidgets('moves focus to the field and says nothing more', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final (_, second, context) = await pump(tester);

      focusOrAnnounce(context, second, 'Enter your password.');
      await tester.pump();

      expect(focused(tester, 'second'), isTrue);
      expect(
        tester.takeAnnouncements().map((a) => a.message),
        isNot(contains('Enter your password.')),
        reason: 'moving focus already reads the field and its message',
      );
      handle.dispose();
    });

    testWidgets('announces the message when the field is already focused', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final (first, _, context) = await pump(tester);
      await tester.tap(find.byKey(const Key('first')));
      await tester.pump();
      tester.takeAnnouncements();

      focusOrAnnounce(context, first, 'Enter your password.');
      await tester.pump();

      expect(focused(tester, 'first'), isTrue);
      expect(
        tester.takeAnnouncements().map((a) => a.message),
        contains('Enter your password.'),
      );
      handle.dispose();
    });

    testWidgets('does nothing when nothing editable is under the key', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final (_, _, context) = await pump(tester);

      focusOrAnnounce(context, GlobalKey(), 'Enter your password.');
      await tester.pump();

      expect(tester.takeAnnouncements(), isEmpty);
      handle.dispose();
    });
  });
}
