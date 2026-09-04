import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';

/// The full-screen state shown while the server builds the first plan.
///
/// Mirrors the prototype's generating artboard (`ScreenOnbInjury` rendered
/// with `generating`), with two deliberate departures from it:
///
/// * the ring is indeterminate, because the server reports no progress; and
/// * every row is driven by work that actually finished, not by a timer. The
///   prototype ticks three rows on a schedule and hardcodes "Avoiding
///   lower-back load" for a user whose injuries it cannot know.
///
/// It cannot be popped: the profile and injury writes have already landed by
/// the time it appears, and backing out would strand the account mid-write
/// with onboarding still incomplete.
class GeneratingView extends StatelessWidget {
  const GeneratingView({
    super.key,
    required this.saved,
    required this.avoiding,
  });

  /// True once the profile and injury writes have returned.
  final bool saved;

  /// The names of the injuries the user reported. Empty omits the row rather
  /// than filling it with copy about an injury nobody has.
  final List<String> avoiding;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

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
                  _CheckRow(id: 'saved', label: 'Profile saved', done: saved),
                  if (avoiding.isNotEmpty)
                    _CheckRow(
                      id: 'avoiding',
                      label: 'Avoiding ${avoiding.join(', ')}',
                      done: saved,
                    ),
                  const _CheckRow(
                    id: 'exercises',
                    label: 'Choosing your exercises',
                    done: false,
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
/// row that has not happened yet reads as pending rather than complete.
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
          Container(
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
