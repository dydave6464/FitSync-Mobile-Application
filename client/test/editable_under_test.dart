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

  testWidgets('returns null when nothing editable is under the key',
      (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Text('no field', key: key))),
    );
    expect(editableUnder(key), isNull);
  });

  test('returns null when the key is not mounted', () {
    expect(editableUnder(GlobalKey()), isNull);
  });
}
