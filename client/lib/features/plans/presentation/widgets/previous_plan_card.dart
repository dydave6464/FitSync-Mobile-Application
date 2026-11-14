import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../domain/workout_plan.dart';
import '../undo_plan.dart';

/// Above the week on the Plan tab while the plan generated last can still be
/// undone: names the plan it replaced and offers it back.
class PreviousPlanCard extends ConsumerWidget {
  const PreviousPlanCard({super.key, required this.previous});

  final PreviousPlan previous;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.fs;
    return FsCard(
      child: Row(
        children: [
          ExcludeSemantics(
            child: Icon(Icons.history, size: 18, color: t.text2),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              "This plan replaced '${previous.name}'.",
              style: TextStyle(fontSize: 12, color: t.text2, height: 1.35),
            ),
          ),
          const SizedBox(width: 8),
          FsButton(
            key: const Key('plan.previous.bringBack'),
            label: 'Bring it back',
            small: true,
            kind: FsButtonKind.secondary,
            onPressed: () => bringBackPreviousPlan(
              messenger: ScaffoldMessenger.of(context),
              container: ProviderScope.containerOf(context, listen: false),
              persist: MediaQuery.accessibleNavigationOf(context),
            ),
          ),
        ],
      ),
    );
  }
}
