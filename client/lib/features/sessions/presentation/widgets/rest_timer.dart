import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import 'rest_sheet.dart';

/// The rest between sets, as the mockup's amber app-bar tag.
///
/// It sits in the bar rather than over the content because that is the one
/// place a workout screen has room for it without pushing the set table
/// around every time a set is ticked.
///
/// Display only. The logger owns the rest (see RestPeriod) and hands this the
/// reading it repaints every second, so the tag and the sheet it opens draw
/// one number and cannot drift apart, and rebuilding the tag cannot restart
/// or stop the rest. Client-only and deliberately not persisted: a rest that
/// elapsed while the app was closed has already elapsed.
class RestTimer extends StatelessWidget {
  const RestTimer({
    super.key,
    required this.reading,
    this.over = false,
    this.onOpen,
  });

  /// The rest's time left.
  final ValueListenable<RestReading?> reading;

  /// The few seconds after a rest runs out: "Rest over" in place of the
  /// countdown, said in words rather than by colour.
  final bool over;

  /// Opens the rest sheet. Null, or [over], leaves the tag inert.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final tappable = onOpen != null && !over;

    final tag = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: t.amber.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(7),
        // The outline and chevron are what say "this opens something": a
        // flat tag reads as a label, and nobody taps a label.
        border: tappable
            ? Border.all(color: t.amber.withValues(alpha: 0.5))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (over)
            Text('Rest over', key: const Key('rest.over'), style: _style(t))
          else ...[
            Text('REST', style: _style(t)),
            const SizedBox(width: 5),
            ValueListenableBuilder<RestReading?>(
              valueListenable: reading,
              builder: (_, value, _) => Text(
                formatRest(value?.secondsLeft ?? 0),
                key: const Key('rest.remaining'),
                style: _style(t),
              ),
            ),
          ],
          if (tappable) ...[
            const SizedBox(width: 2),
            Icon(
              Icons.expand_more,
              key: const Key('rest.affordance'),
              size: 15,
              color: t.text,
            ),
          ],
        ],
      ),
    );

    if (!tappable) return tag;
    // The tag opens the rest sheet -- the countdown, ±30s, Skip, the alert
    // switch and the default for next time. Skip lives in there: one tap
    // cannot both skip and open settings, and skipping by accident while
    // reaching for +30s would be the worse of the two to get wrong.
    return ValueListenableBuilder<RestReading?>(
      valueListenable: reading,
      builder: (_, value, child) => Semantics(
        button: true,
        label: 'Rest timer, ${spokenRest(value?.secondsLeft ?? 0)} left',
        excludeSemantics: true,
        onTap: onOpen,
        child: child,
      ),
      child: InkWell(
        key: const Key('rest.open'),
        onTap: onOpen,
        borderRadius: BorderRadius.circular(7),
        child: ConstrainedBox(
          // The tag is drawn small to sit in the bar, but tapped often:
          // Material's 48dp minimum is the target, not the paint.
          constraints: const BoxConstraints(minHeight: 48),
          child: Center(widthFactor: 1, child: tag),
        ),
      ),
    );
  }

  TextStyle _style(FsTokens t) => TextStyle(
    fontFamily: fsMonoFamily,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.6,
    color: t.text,
  );
}
