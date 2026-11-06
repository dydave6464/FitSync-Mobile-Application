import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/widgets/fs_kit.dart';

/// What is wrong with a number box's [text], or null when it is fine.
/// Blank is fine here: whether a blank box is allowed is the form's call.
/// [range] is how the limits read, e.g. '0–500 g'.
String? numberError(String text, {required double max, required String range}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  final value = double.tryParse(trimmed);
  if (value == null) return 'Enter a number';
  if (value < 0 || value > max) return 'Must be $range';
  return null;
}

/// The most grams of protein, carbs, fat, fiber or sugar, and the most
/// sodium, a food may have per serving (server/src/routes/nutrition.js). The
/// one place both nutrition forms and their error texts take them from.
const maxGrams = 500.0;
const maxSodiumMg = 20000.0;

/// Whether [g] grams is allowed. NaN, which unreadable text parses to, is not.
bool inGramsRange(double g) => g >= 0 && g <= maxGrams;

/// Whether [mg] of sodium is allowed. NaN is not.
bool inSodiumRange(double mg) => mg >= 0 && mg <= maxSodiumMg;

String? gramsError(String text) => numberError(text, max: maxGrams, range: '0–500 g');
String? sodiumError(String text) => numberError(text, max: maxSodiumMg, range: '0–20,000 mg');

/// One number in a nutrition form: its name above the box, and, when
/// [error] is set, what is wrong under it. The error is tied to the box (a
/// screen reader hears it with the box's name) and is read out when it
/// appears.
///
/// Named as the label rule in fs_kit names a field -- the eyebrow
/// `FsField(label:)` draws, heard as the box's own label -- but drawn here
/// so it may take a second line: two boxes share a row, and at large text
/// "SODIUM (MG)" on one line would be cut.
class NumberBox extends StatelessWidget {
  const NumberBox({
    super.key,
    required this.label,
    required this.controller,
    required this.onChanged,
    this.fieldKey,
    this.hint = 'g',
    this.error,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final Key? fieldKey;
  final String hint;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Said once, by the box below, rather than again as its own node.
        ExcludeSemantics(child: FsEyebrow(label, maxLines: 2)),
        const SizedBox(height: 6),
        Semantics(
          label: label,
          child: FsField(
            controller: controller,
            fieldKey: fieldKey,
            hint: hint,
            // A red border, and the message as the box's spoken hint.
            errorText: error,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            onChanged: onChanged,
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 4),
          FsErrorLine(error!),
        ],
      ],
    );
  }
}
