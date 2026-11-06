import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:flutter/services.dart';

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
String clipUtf16(String text, int max) => truncateUtf16(text.trim(), max).trimRight();

/// Stops a field at [max] UTF-16 units, the server's own count. Flutter's
/// LengthLimitingTextInputFormatter counts characters instead, so a name
/// of emoji it let through could be twice as long as the server allows.
class Utf16LengthLimit extends TextInputFormatter {
  const Utf16LengthLimit(this.max);

  final int max;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.length <= max) return newValue;
    final text = truncateUtf16(newValue.text, max);
    final selection = newValue.selection;
    return TextEditingValue(
      text: text,
      selection: selection.copyWith(
        baseOffset: selection.baseOffset.clamp(0, text.length),
        extentOffset: selection.extentOffset.clamp(0, text.length),
      ),
    );
  }
}
