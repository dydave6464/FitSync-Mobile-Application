import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:flutter/services.dart';

/// The longest name and serving a manual food may have, in UTF-16 units
/// (server/src/lib/nutrition-input.js). The one place Add manually and the
/// log sheet's edited food take them from.
const maxFoodName = 100;
const maxServingDesc = 60;

/// [text] cut to at most [max] UTF-16 units -- what the server's length
/// checks count, as JavaScript's `length` does -- without splitting a
/// character: an emoji or an accented letter goes whole or not at all.
String truncateUtf16(String text, int max) {
  if (text.length <= max) return text;
  final out = StringBuffer();
  for (final ch in text.characters) {
    if (out.length + ch.length > max) break;
    out.write(ch);
  }
  return out.toString();
}

/// [text], trimmed and cut to at most [max] UTF-16 units (see
/// [truncateUtf16]), then trimmed again: a name ready to send.
String clipUtf16(String text, int max) =>
    truncateUtf16(text.trim(), max).trimRight();

/// Stops a field at [max] UTF-16 units, the server's own count. Flutter's
/// LengthLimitingTextInputFormatter counts characters instead, so a name
/// of emoji it let through could be twice as long as the server allows.
class Utf16LengthLimit extends TextInputFormatter {
  const Utf16LengthLimit(this.max);

  final int max;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.length <= max) return newValue;
    final old = oldValue.text;
    final at = oldValue.selection.baseOffset;
    // Typed or pasted at the cursor: cut what went in, not the end of the
    // field -- a letter typed mid-text into a full field changes nothing,
    // as with LengthLimitingTextInputFormatter.
    if (oldValue.selection.isValid &&
        oldValue.selection.isCollapsed &&
        old.length <= max &&
        newValue.text.length > old.length &&
        newValue.text.startsWith(old.substring(0, at)) &&
        newValue.text.endsWith(old.substring(at))) {
      final typed = newValue.text.substring(
        at,
        newValue.text.length - (old.length - at),
      );
      final kept = truncateUtf16(typed, max - old.length);
      if (kept.isEmpty) return oldValue;
      final end = at + kept.length;
      return TextEditingValue(
        text: old.substring(0, at) + kept + old.substring(at),
        selection: TextSelection.collapsed(offset: end),
        composing: _clip(newValue.composing, end),
      );
    }
    // Anything else, such as a selection replaced: cut from the end, as
    // LengthLimitingTextInputFormatter.truncate does.
    final text = truncateUtf16(newValue.text, max);
    final selection = newValue.selection;
    return TextEditingValue(
      text: text,
      selection: selection.copyWith(
        baseOffset: selection.baseOffset.clamp(0, text.length),
        extentOffset: selection.extentOffset.clamp(0, text.length),
      ),
      composing: _clip(newValue.composing, text.length),
    );
  }

  /// [composing] cut to end at [end]; empty when nothing of it is left.
  static TextRange _clip(TextRange composing, int end) =>
      composing.isValid && !composing.isCollapsed && composing.start < end
      ? TextRange(
          start: composing.start,
          end: composing.end < end ? composing.end : end,
        )
      : TextRange.empty;
}
