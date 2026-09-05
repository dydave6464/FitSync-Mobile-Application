import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';

/// The full-screen state shown while the server builds the first plan.
///
/// Mirrors the prototype's generating artboard (`ScreenOnbInjury` rendered
/// with `generating`), with two deliberate departures from it:
///
/// * the ring is indeterminate, because the server reports no progress; and
/// * no row ticks before the work it describes has finished. The prototype
///   ticks three rows on a schedule and hardcodes "Avoiding lower-back load"
///   for a user whose injuries it cannot know.
///
/// The schedule below is pacing, not progress. Every gate is still real: the
/// slots decide how early a tick may appear, never whether it is earned. The
/// round trip can finish in under a second, and three ticks landing in one
/// frame reads as a flicker rather than as a system doing something.
///
/// It cannot be popped: the profile and injury writes have already landed by
/// the time it appears, and backing out would strand the account mid-write
/// with onboarding still incomplete.
class GeneratingView extends StatefulWidget {
  const GeneratingView({
    super.key,
    required this.saved,
    required this.planReady,
    required this.avoiding,
  });

  /// The earliest each row may tick, measured from the first frame.
  static const revealAt = <Duration>[
    Duration(milliseconds: 1500),
    Duration(milliseconds: 3500),
    Duration(milliseconds: 5500),
  ];

  /// How long the completed list stays up before the hand-off, so the last
  /// tick is seen rather than replaced by the plan in the same breath.
  static const tail = Duration(milliseconds: 1200);

  /// The shortest this screen can be on show.
  static const minimumRun = Duration(milliseconds: 6700);

  /// True once the profile and injury writes have returned.
  final bool saved;

  /// True once the server has answered with a plan.
  final bool planReady;

  /// The names of the injuries the user reported. Empty is a real answer and
  /// gets its own wording rather than dropping the row.
  final List<String> avoiding;

  @override
  State<GeneratingView> createState() => _GeneratingViewState();
}

class _GeneratingViewState extends State<GeneratingView> {
  final _timers = <Timer>[];

  /// How many slots have opened. A row ticks on `_open > index` and its own
  /// gate, so neither alone is enough.
  int _open = 0;

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < GeneratingView.revealAt.length; i++) {
      _timers.add(Timer(GeneratingView.revealAt[i], () {
        if (mounted) setState(() => _open = i + 1);
      }));
    }
  }

  @override
  void dispose() {
    for (final timer in _timers) {
      timer.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final avoiding = widget.avoiding;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: t.bg,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FsRing(
                    child: Icon(Icons.auto_awesome, size: 34, color: t.accent),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Building your plan…',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Matching exercises to your goals, equipment, '
                    'and injury history.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, height: 1.5, color: t.text2),
                  ),
                  const SizedBox(height: 28),
                  _CheckRow(
                    id: 'saved',
                    label: 'Profile saved',
                    done: widget.saved && _open > 0,
                  ),
                  _CheckRow(
                    id: 'avoiding',
                    label: avoiding.isEmpty
                        ? 'No injuries to work around'
                        : 'Avoiding ${avoiding.join(', ')}',
                    done: widget.saved && _open > 1,
                  ),
                  _CheckRow(
                    id: 'exercises',
                    label: 'Choosing your exercises',
                    done: widget.planReady && _open > 2,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One checklist row. [done] drives both the tick and the text colour, so a
/// row that has not happened yet reads as pending rather than complete. The
/// fill animates because the row now completes while the user is watching it,
/// rather than arriving already ticked.
class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.id,
    required this.label,
    required this.done,
  });

  final String id;
  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? t.accent : t.surface2,
            ),
            child: done
                ? Icon(
                    Icons.check,
                    key: Key('gen.$id.done'),
                    size: 11,
                    color: t.onAccent,
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: done ? t.text : t.text3),
            ),
          ),
        ],
      ),
    );
  }
}
