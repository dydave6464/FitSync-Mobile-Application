import 'package:flutter/material.dart';

/// A line of small text that acts as a button, inside a 48dp tap target.
///
/// The words stay as small as the design draws them; the target around them
/// is what grows, so a thumb that lands just above or below still counts.
/// Every text link on the auth screens is one, so they look and answer alike.
class AuthTextLink extends StatelessWidget {
  const AuthTextLink({super.key, required this.onTap, required this.child});

  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      // Without a tap it is a disabled button, as a TextButton would say.
      enabled: onTap != null,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Align(widthFactor: 1, heightFactor: 1, child: child),
        ),
      ),
    );
  }
}
