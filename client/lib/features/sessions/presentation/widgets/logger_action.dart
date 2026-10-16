import 'package:flutter/material.dart';

import '../../../../core/units.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../../exercises/presentation/exercise_list_screen.dart'
    show describeError;
import 'set_drafts.dart';

/// The logger's one footer button.
///
/// It is the only primary action on the screen, and it changes job rather than
/// multiplying: it logs the set that is next, then offers the exercise that is
/// next, then offers to finish. Naming the set -- "Complete set 3" -- is what
/// makes a single button unambiguous when four rows are on screen.
///
/// The busy and failed state used to live in each row, back when the row's
/// tick was the button. It moved here with the action.
class LoggerAction extends StatefulWidget {
  const LoggerAction({
    super.key,
    required this.activeSetNumber,
    required this.isLastExercise,
    required this.drafts,
    required this.unit,
    required this.onCompleteSet,
    required this.onNextExercise,
    required this.onFinish,
    this.finishing = false,
  });

  /// The set the button will log, or null once the exercise is finished.
  final int? activeSetNumber;

  final bool isLastExercise;
  final SetDrafts drafts;
  final WeightUnit unit;

  final Future<void> Function(int setNumber, double? weightKg, int? reps)
  onCompleteSet;
  final VoidCallback onNextExercise;
  final VoidCallback onFinish;

  /// The session is being completed; the button locks rather than firing twice.
  final bool finishing;

  @override
  State<LoggerAction> createState() => _LoggerActionState();
}

class _LoggerActionState extends State<LoggerAction> {
  bool _busy = false;
  bool _failed = false;

  /// A failure belongs to the set it happened on, and this State outlives a
  /// change of set: reopening a stored row, or jumping to another exercise
  /// that already has sets logged against it, both keep the logging stage
  /// and rebuild this button in place rather than tearing it down. Left
  /// standing, [_failed] would offer to "Retry set 2" for a set nobody has
  /// tried.
  @override
  void didUpdateWidget(LoggerAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    // No setState: didUpdateWidget runs as part of this element's rebuild,
    // so build() reads the cleared flag on the way through. Same shape as
    // _DescribeCard in generator_screen.dart.
    if (widget.activeSetNumber != oldWidget.activeSetNumber) _failed = false;
  }

  Future<void> _complete(int setNumber) async {
    final repsText = widget.drafts.reps(setNumber).text.trim();
    // A set with no reps is almost always a tap that came before the typing,
    // and once stored it is a row nobody can read back. Asked, not refused:
    // a set the user did not count is still a set they did. Weight alone
    // never asks -- a bodyweight set has none.
    if (repsText.isEmpty) {
      final logAnyway = await _confirmNoReps(setNumber);
      if (!mounted) return;
      if (logAnyway != true) {
        if (logAnyway == false) _focusReps(setNumber);
        return;
      }
    }

    setState(() {
      _busy = true;
      _failed = false;
    });
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await widget.onCompleteSet(
        setNumber,
        // An empty field is "not recorded", never zero.
        parseWeight(widget.drafts.weight(setNumber).text, widget.unit),
        int.tryParse(repsText),
      );
    } catch (error) {
      if (mounted) setState(() => _failed = true);
      // "Retry" alone does not say whether to try again now or after
      // finding signal. describeError keeps the wording plain: an
      // ApiException's own message, never an exception's raw text.
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(describeError(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// True to log the set as it stands, false to go back and add reps, null
  /// if the dialog was dismissed -- which, like "Add reps", logs nothing.
  Future<bool?> _confirmNoReps(int setNumber) => showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('logger.noReps'),
      title: Text('Log set $setNumber without reps?'),
      // At large text on a narrow phone the title alone runs to several lines
      // and would push the actions off the dialog; scrolling keeps both
      // answers reachable. The actions already stack when they no longer fit
      // side by side.
      scrollable: true,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Add reps'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Log anyway'),
        ),
      ],
    ),
  );

  /// Puts the caret in this set's reps box, if it is on screen.
  ///
  /// The box belongs to the set row, which keeps no focus node anyone else
  /// can reach; what this widget shares with it is the controller. So the
  /// field is found by that controller -- a one-off walk, taken only after
  /// "Add reps". A row scrolled out of the tree is simply not focused.
  void _focusReps(int setNumber) {
    final controller = widget.drafts.reps(setNumber);
    FocusNode? found;
    void visit(Element element) {
      if (found != null) return;
      final w = element.widget;
      if (w is EditableText && w.controller == controller) {
        found = w.focusNode;
        return;
      }
      element.visitChildElements(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildElements(visit);
    found?.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.activeSetNumber;

    if (active == null) {
      return FsButton(
        key: const Key('logger.primary'),
        label: widget.isLastExercise ? 'Finish session' : 'Next exercise',
        icon: Icon(widget.isLastExercise ? Icons.check : Icons.arrow_forward),
        busy: widget.finishing,
        onPressed: widget.finishing
            ? null
            : (widget.isLastExercise ? widget.onFinish : widget.onNextExercise),
      );
    }

    return FsButton(
      key: const Key('logger.primary'),
      label: _failed ? 'Retry set $active' : 'Complete set $active',
      icon: const Icon(Icons.check),
      busy: _busy,
      onPressed: _busy ? null : () => _complete(active),
    );
  }
}
