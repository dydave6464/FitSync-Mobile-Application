import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../domain/encouragement.dart';

/// The message under a fully logged set table.
///
/// Styled like the panel's progressive-overload note, which is the other
/// thing this screen says about how the workout is going -- two kinds of
/// praise drawn two ways would read as two features.
class EncouragementCard extends StatelessWidget {
  const EncouragementCard({super.key, required this.message});

  final Encouragement message;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final detail = message.detail;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: t.accentDim,
        borderRadius: BorderRadius.circular(FsRadius.md),
        border: Border.all(color: t.accentLine),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.emoji_events_outlined, size: 16, color: t.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.headline,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: t.text,
                    height: 1.35,
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 3),
                  Text(detail, style: TextStyle(fontSize: 11, color: t.text2)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
