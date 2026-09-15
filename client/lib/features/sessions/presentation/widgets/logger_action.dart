import 'package:flutter/material.dart';

import '../../../../core/units.dart';
import '../../../../core/widgets/fs_kit.dart';
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

  Future<void> _complete(int setNumber) async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await widget.onCompleteSet(
        setNumber,
        // An empty field is "not recorded", never zero.
        parseWeight(widget.drafts.weight(setNumber).text, widget.unit),
        int.tryParse(widget.drafts.reps(setNumber).text.trim()),
      );
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
