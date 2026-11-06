import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/nutrition/presentation/widgets/text_limits.dart';

// L-62: the server counts a name's length in UTF-16 units, as JavaScript
// does; Flutter's LengthLimitingTextInputFormatter counts characters, so
// "😀" x 60 got through as 60 though the server sees 120.
void main() {
  // P-5: one definition for Add manually and the log sheet.
  test("a manual food's name and serving limits are the server's", () {
    expect(maxFoodName, 100);
    expect(maxServingDesc, 60);
  });

  group('clipUtf16', () {
    test('leaves a short text alone, trimmed', () {
      expect(clipUtf16('  Turon ', 100), 'Turon');
    });

    test('counts UTF-16 units, as the server does', () {
      final clipped = clipUtf16('😀' * 60, 100);
      expect(clipped.length, 100);
      expect(clipped, '😀' * 50);
    });

    test('never splits a character to fit', () {
      // 9 units allowed, each emoji is 2: four whole, not four and a half.
      expect(clipUtf16('😀' * 5, 9), '😀' * 4);
      // A family is one character of 8 units: it goes whole or not at all.
      const family = '👨‍👩‍👧';
      expect(clipUtf16('ab$family', 9), 'ab');
    });
  });

  group('Utf16LengthLimit', () {
    TextEditingValue format(String old, String typed, int max) =>
        Utf16LengthLimit(max).formatEditUpdate(
          TextEditingValue(
            text: old,
            selection: TextSelection.collapsed(offset: old.length),
          ),
          TextEditingValue(
            text: typed,
            selection: TextSelection.collapsed(offset: typed.length),
          ),
        );

    test('keeps text within the limit as typed', () {
      final v = format('Tur', 'Turon', 10);
      expect(v.text, 'Turon');
      expect(v.selection, const TextSelection.collapsed(offset: 5));
    });

    test(
      'cuts pasted text to the limit in UTF-16 units, whole characters only',
      () {
        final v = format('', '😀' * 60, 100);
        expect(v.text, '😀' * 50);
        expect(v.selection, const TextSelection.collapsed(offset: 100));
      },
    );

    test('keeps the old text when a character would not fit at all', () {
      final full = 'a' * 99;
      final v = format(full, '$full😀', 100);
      expect(v.text, full);
    });

    // Flutter's LengthLimitingTextInputFormatter keeps the old text when a
    // full field is typed into; cutting from the end instead dropped the
    // field's last character whenever a letter went in mid-text.
    TextEditingValue insertAt(String old, int at, String typed, int max) =>
        Utf16LengthLimit(max).formatEditUpdate(
          TextEditingValue(
            text: old,
            selection: TextSelection.collapsed(offset: at),
          ),
          TextEditingValue(
            text: old.substring(0, at) + typed + old.substring(at),
            selection: TextSelection.collapsed(offset: at + typed.length),
          ),
        );

    test('a letter typed mid-text into a full field changes nothing', () {
      final full = '${'a' * 59}Z';
      final v = insertAt(full, 30, 'x', 60);
      expect(v.text, full);
      expect(v.selection, const TextSelection.collapsed(offset: 30));
    });

    test('a paste mid-text keeps the end of the field, cutting the paste', () {
      // 7 units of room: three whole emoji go in, the text after the
      // cursor stays.
      final v = insertAt('${'a' * 50}END', 50, '😀' * 6, 60);
      expect(v.text, '${'a' * 50}${'😀' * 3}END');
      expect(v.selection, const TextSelection.collapsed(offset: 56));
    });

    test('keeps the IME composing range inside what is kept', () {
      final v = Utf16LengthLimit(5).formatEditUpdate(
        const TextEditingValue(
          text: 'ab',
          selection: TextSelection.collapsed(offset: 2),
        ),
        const TextEditingValue(
          text: 'abcdefg',
          selection: TextSelection.collapsed(offset: 7),
          composing: TextRange(start: 2, end: 7),
        ),
      );
      expect(v.text, 'abcde');
      expect(v.composing, const TextRange(start: 2, end: 5));
    });

    test('a selection replaced by a long paste is cut to the limit', () {
      final v = Utf16LengthLimit(6).formatEditUpdate(
        const TextEditingValue(
          text: 'abcdef',
          selection: TextSelection(baseOffset: 0, extentOffset: 6),
        ),
        const TextEditingValue(
          text: 'xyzxyzxyz',
          selection: TextSelection.collapsed(offset: 9),
        ),
      );
      expect(v.text, 'xyzxyz');
      expect(v.selection, const TextSelection.collapsed(offset: 6));
    });
  });
}
