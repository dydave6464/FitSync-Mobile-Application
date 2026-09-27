import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/fs_kit.dart';

/// What the app says for any refused code: the server gives one answer for
/// wrong, expired and used-up codes alike, so this does too.
const wrongCodeMessage =
    'That code is wrong or has expired. Check your latest email, or send a '
    'new code.';

/// After "Send a new code" on the verification screen. The server answers
/// the same whether it sent one or its one-per-minute limit held it back, so
/// this never claims more than that one is coming.
const newCodeMessage = 'A new code is on its way. Check your inbox (and spam).';

/// A 6-digit code field: digits only (a pasted "048 213" becomes "048213"),
/// at most six, the number keypad, and the platform's one-time-code autofill.
class CodeField extends StatelessWidget {
  const CodeField({
    super.key,
    required this.controller,
    this.fieldKey = const Key('code'),
  });

  final TextEditingController controller;
  final Key fieldKey;

  @override
  Widget build(BuildContext context) => FsField(
    fieldKey: fieldKey,
    controller: controller,
    hint: '6-digit code',
    icon: Icons.pin_outlined,
    keyboardType: TextInputType.number,
    textInputAction: TextInputAction.done,
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(6),
    ],
    autofillHints: const [AutofillHints.oneTimeCode],
  );
}
