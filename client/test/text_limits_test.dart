import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/nutrition/presentation/widgets/text_limits.dart';

// L-62: the server counts a name's length in UTF-16 units, as JavaScript
// does; Flutter's LengthLimitingTextInputFormatter counts characters, so
// "😀" x 60 got through as 60 though the server sees 120.
void main() {
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
    TextEditingValue format(String old, String typed, int max) => Utf16LengthLimit(max).formatEditUpdate(
          TextEditingValue(text: old, selection: TextSelection.collapsed(offset: old.length)),
          TextEditingValue(text: typed, selection: TextSelection.collapsed(offset: typed.length)),
        );

    test('keeps text within the limit as typed', () {
      final v = format('Tur', 'Turon', 10);
      expect(v.text, 'Turon');
      expect(v.selection, const TextSelection.collapsed(offset: 5));
    });

    test('cuts pasted text to the limit in UTF-16 units, whole characters only', () {
      final v = format('', '😀' * 60, 100);
      expect(v.text, '😀' * 50);
      expect(v.selection, const TextSelection.collapsed(offset: 100));
    });

    test('keeps the old text when a character would not fit at all', () {
      final full = 'a' * 99;
      final v = format(full, '$full😀', 100);
      expect(v.text, full);
    });
  });
}
