import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../nutrition/domain/meal_suggestion.dart';
import '../../profile/presentation/providers.dart';

/// Settings › Rice with meals: the cups suggested plates carry, saved on tap
/// (spec 2026-11-13, 1.4).
Future<void> showRiceWithMealsSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: false,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const FsSheetHeightCap(child: _RiceSheet()),
    );

class _RiceSheet extends ConsumerStatefulWidget {
  const _RiceSheet();

  @override
  ConsumerState<_RiceSheet> createState() => _RiceSheetState();
}

class _RiceSheetState extends ConsumerState<_RiceSheet> {
  /// The amount on its way to the server, drawn in place of the saved one.
  double? _pending;

  /// Set when the last save was refused; cleared by the next tap.
  bool _failed = false;

  /// Saves as the Weight unit switch does: the new amount shows at once,
  /// further taps wait for the answer, and a refused save goes back and says
  /// so. `ProfileNotifier.patch` refetches the suggestions itself.
  Future<void> _save(double cups) async {
    if (_pending != null) return;
    setState(() {
      _pending = cups;
      _failed = false;
    });
    // Captured before the await: the sheet can be closed while the save runs
    // (the close button, the scrim, a drag, system back), and the app-level
    // messenger outlives it.
    final messenger = ScaffoldMessenger.of(context);
    final route = ModalRoute.of(context);
    try {
      await ref.read(profileProvider.notifier).patch({'usualRiceCups': cups});
    } catch (error) {
      // The sheet says only that it failed; anything the API layer did not
      // name is logged for why.
      if (error is! ApiException) {
        debugPrint('Saving $cups cups of rice failed: $error');
      }
      // On the sheet while it is open; once it is closing or closed, as a
      // snack bar on the screen under it, so the failure is never silent.
      if (mounted && (route?.isCurrent ?? false)) {
        setState(() => _failed = true);
      } else {
        messenger.showSnackBar(
          const SnackBar(content: Text("Couldn't save your rice. Try again.")),
        );
      }
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final saved = ref.watch(profileProvider).value?.usualRiceCups ?? 1;
    final shown = _pending ?? saved;
    // Scrolls rather than overflows when large text makes it taller than
    // the sheet may be.
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          FsSheetHeader.sideInset,
          10,
          FsSheetHeader.sideInset,
          12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FsSheetHeader(title: 'Rice with meals'),
            const SizedBox(height: 8),
            Text(
              'Used for suggested plates. You can change it when you log a plate.',
              style: TextStyle(fontSize: 12.5, color: t.text2),
            ),
            const SizedBox(height: 12),
            // Wraps at large text rather than shrinking a label. FsTapRoom
            // lets each chip's 48 dp band reach past the row, as on the Log
            // sheet's rice line.
            FsTapRoom(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final cups in riceChoices)
                    FsChip(
                      key: Key('rice.$cups'),
                      label: cups == 0 ? 'None' : cupsLabel(cups),
                      selected: shown == cups,
                      exclusive: true,
                      onTap: _pending == null ? () => _save(cups) : null,
                    ),
                ],
              ),
            ),
            // FsTapRoom's reach below the row: room inside the column, which
            // hit-tests only its own box, not the padding around it.
            const SizedBox(height: 8),
            // In the sheet while it is open, not a snack bar: one would be
            // drawn under it. FsErrorLine is a live region, so it is read out.
            if (_failed) ...[
              const FsErrorLine("Couldn't save your rice. Try again."),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}
