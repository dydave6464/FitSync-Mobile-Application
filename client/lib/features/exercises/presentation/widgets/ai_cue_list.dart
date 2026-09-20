import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../domain/exercise_cues.dart';

/// The mockup's numbered cue cards.
///
/// The heading and the pill both depend on where the cues came from. Claiming
/// "AI coaching cues" over the catalogue's own seeded text would be a lie the
/// reader has no way to check, so the two states say different things and the
/// pill -- the injury these were written for -- appears only when there is one.
class AiCueList extends StatelessWidget {
  const AiCueList({super.key, required this.cues});

  final ExerciseCues cues;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    // An exercise with no cues at all shows no heading either, rather than a
    // section title over nothing.
    if (cues.cues.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (cues.isAi) ...[
              Icon(Icons.auto_awesome, size: 16, color: t.accent),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                cues.isAi ? 'AI coaching cues' : 'How to perform',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: t.text,
                ),
              ),
            ),
            if (cues.injuryName != null) FsTag(cues.injuryName!),
          ],
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < cues.cues.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: FsCard(
              padding: const EdgeInsets.all(11),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontFamily: fsMonoFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: t.accent,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cues.cues[i].title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: t.text,
                          ),
                        ),
                        if (cues.cues[i].detail != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            cues.cues[i].detail!,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: t.text3,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
