import 'package:flutter/material.dart';

import '../../../../core/theme.dart';

/// "✦ Knee · AI coached": this exercise works an injured area and comes with
/// AI cues written for that injury. Worded as what the app does, not as a
/// risk claim -- the app does not diagnose which exercises cause injury.
class CoachingTag extends StatelessWidget {
  const CoachingTag({super.key, required this.injuryName});

  final String injuryName;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: t.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(FsRadius.pill),
        border: Border.all(color: t.accentLine),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome, size: 11, color: t.accent),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '$injuryName · AI coached',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: t.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
