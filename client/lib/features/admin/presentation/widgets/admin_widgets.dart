import 'package:flutter/material.dart';

import '../../../../core/numbers.dart';
import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../domain/admin_format.dart';

/// A change in words a screen reader says: "up 3", "down ₱249",
/// "no change". [deltaCount] when it is a count; otherwise [deltaPhp].
String changeWords({required int? deltaCount, double? deltaPhp}) {
  if (deltaCount != null) {
    if (deltaCount == 0) return 'no change';
    final size = groupThousands(deltaCount.abs().toDouble());
    return deltaCount > 0 ? 'up $size' : 'down $size';
  }
  final php = deltaPhp ?? 0;
  if (formatPhp(php.abs()) == formatPhp(0)) return 'no change';
  return php > 0 ? 'up ${formatPhp(php)}' : 'down ${formatPhp(-php)}';
}

/// "+3 ↑", "−₱249 ↓", "No change": a change shown by its sign and an arrow,
/// in the accent for a rise and the error red for a fall, so colour is
/// never the only clue. Never a percentage.
///
/// Read aloud as [semanticsPrefix] then the change in words, e.g.
/// "Change from last month: up ₱747".
class ChangeLine extends StatelessWidget {
  const ChangeLine({
    super.key,
    required this.deltaCount,
    this.deltaPhp,
    required this.semanticsPrefix,
  });

  /// A change in a count; null when the change is in pesos ([deltaPhp]).
  final int? deltaCount;
  final double? deltaPhp;
  final String semanticsPrefix;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final words = changeWords(deltaCount: deltaCount, deltaPhp: deltaPhp);
    final direction = words.startsWith('up')
        ? 1
        : words.startsWith('down')
        ? -1
        : 0;
    final color = switch (direction) {
      1 => t.accentText,
      -1 => t.red,
      _ => t.text3,
    };
    final text = direction == 0
        ? 'No change'
        : deltaCount != null
        ? signedCount(deltaCount!)
        : signedPhp(deltaPhp ?? 0);

    return Semantics(
      label: '$semanticsPrefix $words',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(text, style: fsNum(t, size: 12).copyWith(color: color)),
          ),
          if (direction != 0) ...[
            const SizedBox(width: 2),
            Icon(
              direction > 0 ? Icons.arrow_upward : Icons.arrow_downward,
              size: 14,
              color: color,
            ),
          ],
        ],
      ),
    );
  }
}

/// A trainee's initials in a 40 dp circle, as Home's greeting draws the
/// trainee's own.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar(this.fullName, {super.key});

  final String fullName;

  String get _initials {
    // Greeting's rule: first and last word, "?" for no name at all.
    final words = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) return words.first[0].toUpperCase();
    return (words.first[0] + words.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return ExcludeSemantics(
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: t.surface2,
          shape: BoxShape.circle,
          border: Border.all(color: t.line),
        ),
        // Scaled down rather than painted past the circle at large text.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            _initials,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: t.text2,
            ),
          ),
        ),
      ),
    );
  }
}

/// [FsTag]'s pill with its word in [color]: "Pro", "Suspended" in red. The
/// word is always there, so the colour is never the only clue.
class StatusTag extends StatelessWidget {
  const StatusTag(this.text, {super.key, this.color, this.dot});

  final String text;

  /// Null is the tag's usual dim text.
  final Color? color;

  /// A small dot of this colour before the word, for a colour too faint to
  /// be read as text (the light theme's amber is 2.5:1 on the tag).
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final word = Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        color: color ?? t.text2,
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(FsRadius.pill),
        border: Border.all(color: t.line),
      ),
      child: dot == null
          ? word
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                Flexible(child: word),
              ],
            ),
    );
  }
}

/// What an admin list shows when it has nothing: a plain sentence and,
/// when there is a way out, one button under it.
class AdminEmpty extends StatelessWidget {
  const AdminEmpty({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.actionKey,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Key? actionKey;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, height: 1.45, color: t.text2),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 12),
            FsButton(
              key: actionKey,
              label: actionLabel!,
              small: true,
              kind: FsButtonKind.secondary,
              onPressed: onAction,
            ),
          ],
        ],
      ),
    );
  }
}
