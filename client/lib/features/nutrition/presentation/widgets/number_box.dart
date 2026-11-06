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

String? gramsError(String text) => numberError(text, max: 500, range: '0–500 g');
String? sodiumError(String text) => numberError(text, max: 20000, range: '0–20,000 mg');

/// One number in a nutrition form: its name above the box, and, when
/// [error] is set, what is wrong under it. The error is tied to the box (a
/// screen reader hears it with the box's name) and is read out when it
/// appears.
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
    final t = context.fs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Said once, by the box below, rather than again as its own node.
        ExcludeSemantics(child: Text(label, style: TextStyle(color: t.text2, fontSize: 12))),
        const SizedBox(height: 4),
        Semantics(
          label: label,
          hint: error,
          child: FsField(
            controller: controller,
            fieldKey: fieldKey,
            hint: hint,
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
