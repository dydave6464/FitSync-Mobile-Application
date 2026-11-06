import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// Pushes a goal sheet (the add-goal sheet or one goal's sheet): what
/// [showModalBottomSheet] would push, sized for the keyboard, but through
/// [_GoalSheetRoute], so a tap on the scrim closes the sheet on any step.
Future<void> pushGoalSheet(BuildContext context, WidgetBuilder builder) {
  final navigator = Navigator.of(context);
  final localizations = MaterialLocalizations.of(context);
  return navigator.push(
    _GoalSheetRoute(
      builder: builder,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      // Material's 48 dp would push a sheet sized to the room above the keyboard off the top (PT-22).
      showDragHandle: false,
      backgroundColor: context.fs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      isScrollControlled: true,
      barrierLabel: localizations.scrimLabel,
      barrierOnTapHint: localizations.scrimOnTapHint(
        localizations.bottomSheetLabel,
      ),
      modalBarrierColor: Theme.of(context).bottomSheetTheme.modalBarrierColor,
    ),
  );
}

/// The sheet's route, whose scrim closes it outright.
///
/// A second step holds the phone's back in a [PopScope] to step back, and
/// the stock scrim asks that same [PopScope] (it calls
/// `Navigator.maybePop`), so a tap outside the sheet stepped back rather
/// than closing it. The scrim here pops the route itself, as a drag down
/// already does, keeping everything else the stock scrim has: its colour
/// animation, label, tap hint and semantics clip.
class _GoalSheetRoute extends ModalBottomSheetRoute<void> {
  _GoalSheetRoute({
    required super.builder,
    required super.isScrollControlled,
    super.capturedThemes,
    super.barrierLabel,
    super.barrierOnTapHint,
    super.backgroundColor,
    super.shape,
    super.modalBarrierColor,
    super.showDragHandle,
  });

  /// What a drag down does (BottomSheet's onClosing): a pop that does not
  /// ask the [PopScope].
  void _close() {
    if (isCurrent) navigator?.pop();
  }

  @override
  Widget buildModalBarrier() {
    final barrier = super.buildModalBarrier();
    return switch (barrier) {
      AnimatedModalBarrier() => AnimatedModalBarrier(
        color: barrier.color,
        dismissible: barrier.dismissible,
        semanticsLabel: barrier.semanticsLabel,
        barrierSemanticsDismissible: barrier.barrierSemanticsDismissible,
        clipDetailsNotifier: barrier.clipDetailsNotifier,
        semanticsOnTapHint: barrier.semanticsOnTapHint,
        onDismiss: _close,
      ),
      ModalBarrier() => ModalBarrier(
        color: barrier.color,
        dismissible: barrier.dismissible,
        semanticsLabel: barrier.semanticsLabel,
        barrierSemanticsDismissible: barrier.barrierSemanticsDismissible,
        clipDetailsNotifier: barrier.clipDetailsNotifier,
        semanticsOnTapHint: barrier.semanticsOnTapHint,
        onDismiss: _close,
      ),
      _ => barrier,
    };
  }
}
