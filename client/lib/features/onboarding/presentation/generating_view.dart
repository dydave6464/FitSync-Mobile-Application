import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';

/// How long the checklist takes to reveal itself.
///
/// Pacing, never progress: the gates decide how EARLY a row may tick, never
/// whether it has been earned. A round trip can finish in under a second, and
/// three ticks landing in one frame reads as a flicker rather than as a system
/// doing something.
enum GeneratingPace {
  /// Once, at the end of onboarding, where the wait is the product
  /// introducing itself.
  onboarding(
    revealAt: [
      Duration(milliseconds: 1500),
      Duration(milliseconds: 3500),
      Duration(milliseconds: 5500),
    ],
    tail: Duration(milliseconds: 1200),
  ),

  /// From the generator, which a user may run repeatedly while tuning a
  /// split. Roughly half, because the same seven seconds that reassure once
  /// grate on the fourth attempt.
  regenerate(
    revealAt: [
      Duration(milliseconds: 800),
      Duration(milliseconds: 1800),
      Duration(milliseconds: 2800),
    ],
    tail: Duration(milliseconds: 600),
  );

  const GeneratingPace({required this.revealAt, required this.tail});

  /// The earliest each row may tick, measured from the first frame.
  final List<Duration> revealAt;

  /// How long the completed list stays up before the hand-off, so the last
  /// tick is seen rather than replaced in the same breath.
  final Duration tail;

  /// The shortest this screen can be on show.
  Duration get minimumRun => revealAt.last + tail;

  /// How much longer the screen still owes the user, given the moment it
  /// first appeared.
  ///
  /// One definition rather than one per caller: the screen paces its own
  /// reveals, so handing off on the server's timing alone would cut the list
  /// off mid-sequence — usually before a single row had ticked, since the
  /// round trip can finish in under a second. Two cases: a fast build waits
  /// out the whole schedule, and a slow one has already passed the last slot,
  /// so it only owes the tail.
  Duration remainingFrom(DateTime since) {
    final elapsed = DateTime.now().difference(since);
    return elapsed < revealAt.last ? minimumRun - elapsed : tail;
  }

  /// Waits out [remainingFrom], or returns at once when nothing is owed.
  Future<void> hold(DateTime since) async {
    final remaining = remainingFrom(since);
    if (remaining > Duration.zero) await Future<void>.delayed(remaining);
  }
}

/// The full-screen state shown while the server builds a plan.
///
/// Mirrors the prototype's generating artboard (`ScreenOnbInjury` rendered
/// with `generating`), with two deliberate departures from it:
///
/// * the ring is indeterminate, because the server reports no progress; and
/// * no row ticks before the work it describes has finished. The prototype
///   ticks three rows on a schedule and hardcodes "Avoiding lower-back load"
///   for a user whose injuries it cannot know.
///
/// The schedule is pacing, not progress — see [GeneratingPace].
///
/// Three rows, each with one job and no fallback between them: [leadLabel]
/// says what is being applied, the second row always reports the injuries
/// being worked around (in both of its states), and the third waits for the
/// plan itself.
///
/// Used from two places. Onboarding runs it at [GeneratingPace.onboarding]
/// and cannot be popped: the profile and injury writes have already landed by
/// the time it appears, and backing out would strand the account mid-write
/// with onboarding still incomplete. The generator runs it at
/// [GeneratingPace.regenerate], where nothing is half-written and backing out
/// is allowed.
class GeneratingView extends StatefulWidget {
  const GeneratingView({
    super.key,
    required this.title,
    required this.subtitle,
    required this.leadLabel,
    required this.leadDone,
    required this.avoiding,
    required this.planReady,
    this.pace = GeneratingPace.onboarding,
    this.canPop = false,
  });

  /// The headline: what is happening.
  final String title;

  /// The line under it: how it is being decided.
  final String subtitle;

  /// The first row's sentence. Onboarding reports the write it just made;
  /// the generator states the split and schedule being applied.
  final String leadLabel;

  /// True once whatever [leadLabel] claims has actually happened.
  final bool leadDone;

  /// The names of the injuries the user reported. Empty is a real answer and
  /// gets its own wording rather than dropping the row.
  final List<String> avoiding;

  /// True once the server has answered with a plan.
  final bool planReady;

  /// How early the rows may tick.
  final GeneratingPace pace;

  /// Whether a back gesture may leave the screen. False where leaving would
  /// strand a half-written account.
  final bool canPop;

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
    final revealAt = widget.pace.revealAt;
    for (var i = 0; i < revealAt.length; i++) {
      _timers.add(
        Timer(revealAt[i], () {
          if (mounted) setState(() => _open = i + 1);
        }),
      );
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
      canPop: widget.canPop,
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
                    widget.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, height: 1.5, color: t.text2),
                  ),
                  const SizedBox(height: 28),
                  _CheckRow(
                    id: 'lead',
                    label: widget.leadLabel,
                    done: widget.leadDone && _open > 0,
                  ),
                  _CheckRow(
                    id: 'avoiding',
                    label: avoiding.isEmpty
                        ? 'No injuries to work around'
                        : 'Avoiding ${avoiding.join(', ')}',
                    done: widget.leadDone && _open > 1,
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
  const _CheckRow({required this.id, required this.label, required this.done});

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
