import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../domain/workout_plan.dart';
import '../undo_plan.dart';

/// Above the week on the Plan tab while the plan generated last can still be
/// undone: names the plan it replaced and offers it back.
class PreviousPlanCard extends ConsumerStatefulWidget {
  const PreviousPlanCard({super.key, required this.previous});

  final PreviousPlan previous;

  @override
  ConsumerState<PreviousPlanCard> createState() => _PreviousPlanCardState();
}

class _PreviousPlanCardState extends ConsumerState<PreviousPlanCard> {
  /// On from the tap until the ask fails or the plan has reloaded: the old
  /// plan stays on screen while it reloads, and a second ask in that time
  /// would only be refused.
  bool _busy = false;

  Future<void> _bringBack() async {
    setState(() => _busy = true);
    try {
      await bringBackPreviousPlan(
        messenger: ScaffoldMessenger.of(context),
        container: ProviderScope.containerOf(context, listen: false),
        persist: MediaQuery.accessibleNavigationOf(context),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final text = Text(
      "This plan replaced '${widget.previous.name}'.",
      style: TextStyle(fontSize: 12, color: t.text2, height: 1.35),
    );
    final button = FsButton(
      key: const Key('plan.previous.bringBack'),
      label: 'Bring it back',
      small: true,
      kind: FsButtonKind.secondary,
      busy: _busy,
      onPressed: _bringBack,
    );
    final icon = ExcludeSemantics(
      child: Icon(Icons.history, size: 18, color: t.text2),
    );
    return FsCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Side by side only while the words keep a readable width beside
          // the button; with large text on a narrow phone the button moves
          // under them instead of squeezing them to a column.
          final scaler = MediaQuery.textScalerOf(context);
          final fitsInRow = constraints.maxWidth >= scaler.scale(300);
          if (fitsInRow) {
            return Row(
              children: [
                icon,
                const SizedBox(width: 11),
                Expanded(child: text),
                const SizedBox(width: 8),
                button,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  icon,
                  const SizedBox(width: 11),
                  Expanded(child: text),
                ],
              ),
              const SizedBox(height: 8),
              // IntrinsicWidth: the button hugs its label, as it does in the
              // row, instead of spreading across the card.
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: IntrinsicWidth(child: button),
              ),
            ],
          );
        },
      ),
    );
  }
}
