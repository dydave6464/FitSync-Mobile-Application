import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// The eye inside a password field, as on the sign-in form: shows or hides
/// what was typed, so a mistyped character can be found without retyping it
/// all. 48 dp, and named for what a tap does ("Show password").
class PasswordRevealToggle extends StatelessWidget {
  const PasswordRevealToggle({
    super.key,
    required this.obscured,
    required this.onPressed,
    this.what = 'password',
  });

  /// Whether the field is hiding its text now.
  final bool obscured;
  final VoidCallback onPressed;

  /// What the field holds, for the tooltip: "Show new password".
  final String what;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: obscured ? 'Show $what' : 'Hide $what',
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      icon: Icon(
        obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        size: 20,
        color: context.fs.text2,
      ),
      onPressed: onPressed,
    );
  }
}
