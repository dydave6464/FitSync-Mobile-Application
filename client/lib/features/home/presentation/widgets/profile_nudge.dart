import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../../profile/domain/profile.dart';

/// Whether the user skipped something that degrades their generated plan.
///
/// Exposed as a function, not just a private getter, because HomeScreen needs
/// the same answer to decide whether to leave a gap for the nudge.
///
/// Injuries are deliberately not a trigger: an empty injury list is a normal
/// answer, not a gap.
bool profileNeedsFinishing(Profile profile) =>
    profile.mainGoal == null ||
    profile.fitnessLevel == null ||
    profile.equipment.isEmpty;

/// Shown when [profileNeedsFinishing]. Onboarding steps carry a Skip control,
/// so a user can reach Home with no goal and no equipment.
class ProfileNudge extends StatelessWidget {
  const ProfileNudge({super.key, required this.profile, required this.onTap});

  final Profile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (!profileNeedsFinishing(profile)) return const SizedBox.shrink();

    final t = context.fs;
    final theme = Theme.of(context);

    return FsCard(
      small: true,
      accent: true,
      onTap: onTap,
      child: Row(
        children: [
          const FsIconTile(icon: Icons.auto_awesome, selected: true),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Finish your profile',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  'Using safe defaults — add your goal and equipment for a '
                  'better plan.',
                  style: TextStyle(fontSize: 11, color: t.text3),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 16, color: t.accent),
        ],
      ),
    );
  }
}
