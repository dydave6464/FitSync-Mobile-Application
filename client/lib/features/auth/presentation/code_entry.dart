import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/api_exception.dart';
import '../../../core/widgets/fs_kit.dart';
import '../data/auth_repository.dart';
import '../domain/auth_user.dart';

/// What the app says for any refused code: the server gives one answer for
/// wrong, expired and used-up codes alike, so this does too.
const wrongCodeMessage =
    'That code is wrong or has expired. Check your latest email, or send a '
    'new code.';

/// After "Send a new code" on the verification screen. The server answers
/// the same whether it sent one or its one-per-minute limit held it back, so
/// this never claims more than that one is coming.
const newCodeMessage = 'A new code is on its way. Check your inbox (and spam).';

/// The banners shown once a correct code has signed someone in. Without them
/// the code screen simply gives way to onboarding or Home, with nothing to say
/// the code worked.
const verifiedSignInMessage = "Email verified — you're signed in.";
const resetSignInMessage = "Password updated — you're signed in.";

/// Shows [message] as a floating banner that slides in and out by itself.
/// Takes the messenger rather than a context: the code screen has closed by
/// the time this runs, and the app-wide messenger shows it on whatever screen
/// took its place.
void showSignedInBanner(ScaffoldMessengerState messenger, String message) {
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
      content: Row(
        children: [
          const Icon(Icons.check_circle_outline, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}

/// The one sign-in tried when a code comes back CODE_INVALID. If the server
/// accepted the code but its reply was lost, a retry finds the code spent on
/// an account that is in fact verified or reset, and only a sign-in can tell.
/// Null when that sign-in fails too -- then the code really was wrong.
Future<AuthUser?> signInAfterRejectedCode(
  AuthRepository repo,
  String email,
  String password,
) async {
  try {
    return await repo.login(email, password);
  } on ApiException {
    return null;
  }
}

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
