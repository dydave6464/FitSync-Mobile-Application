import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme.dart';
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
/// sodium, a food may have per serving (server/src/lib/nutrition-input.js).
/// The one place both nutrition forms and their error texts take them from.
const maxGrams = 500.0;
const maxSodiumMg = 20000.0;

/// Whether [g] grams is allowed. NaN, which unreadable text parses to, is not.
bool inGramsRange(double g) => g >= 0 && g <= maxGrams;

/// Whether [mg] of sodium is allowed. NaN is not.
bool inSodiumRange(double mg) => mg >= 0 && mg <= maxSodiumMg;

/// How a range from 0 to [max] reads in an error: '0–20,000 mg'.
String rangeText(double max, String unit) {
  final digits = max.round().toString();
  final grouped = digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');
  return '0–$grouped $unit';
}

String? gramsError(String text) => numberError(text, max: maxGrams, range: rangeText(maxGrams, 'g'));
String? sodiumError(String text) => numberError(text, max: maxSodiumMg, range: rangeText(maxSodiumMg, 'mg'));

/// The most calories per serving a label may give a manual food
/// (MAX_KCAL in server/src/lib/nutrition-input.js).
const maxKcal = 5000.0;

/// Whether [kcal] is allowed. NaN is not.
bool inKcalRange(double kcal) => kcal >= 0 && kcal <= maxKcal;

String? kcalError(String text) => numberError(text, max: maxKcal, range: rangeText(maxKcal, 'kcal'));

/// One number in a nutrition form: its name above the box, and, when
/// [error] is set, what is wrong under it. The error is tied to the box (a
/// screen reader hears it with the box's name) and is read out when it
/// appears.
///
/// Carries its own name, as the label rule in fs_kit says: the small dim
/// label the prototype draws over its macro boxes ('dim t-xs', weight 600),
/// not an eyebrow, heard as the box's own label. It may take a second line:
/// two boxes share a row, and at large text "Sodium (mg)" on one line would
/// be cut.
class NumberBox extends StatelessWidget {
  const NumberBox({
    super.key,
    required this.label,
    required this.controller,
    required this.onChanged,
    this.fieldKey,
    this.hint = 'g',
    this.error,
    this.wholeNumbers = false,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final Key? fieldKey;
  final String hint;
  final String? error;

  /// Digits only, with a keyboard that has no decimal point (calories).
  final bool wholeNumbers;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Said once, by the box below, rather than again as its own node.
        ExcludeSemantics(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: t.text2, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 6),
        Semantics(
          label: label,
          child: FsField(
            controller: controller,
            fieldKey: fieldKey,
            hint: hint,
            // A red border, and the message as the box's spoken hint.
            errorText: error,
            keyboardType: TextInputType.numberWithOptions(decimal: !wholeNumbers),
            inputFormatters: [
              wholeNumbers ? FilteringTextInputFormatter.digitsOnly : FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
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
