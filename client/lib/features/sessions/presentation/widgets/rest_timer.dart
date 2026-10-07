import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import 'rest_sheet.dart';

/// The countdown between sets, as the mockup's amber app-bar tag.
///
/// It sits in the bar rather than over the content because that is the one
/// place a workout screen has room for it without pushing the set table
/// around every time a set is ticked.
///
/// Client-only and deliberately not persisted: a rest period that elapsed
/// while the app was closed has already elapsed, so restoring one after a
/// force-quit would be theatre. (The length a rest STARTS at is saved -- see
/// restSecondsProvider -- but a countdown in progress is not.)
class RestTimer extends StatefulWidget {
  const RestTimer({
    super.key,
    required this.duration,
    required this.onDone,
    this.onSkip,
  });

  final Duration duration;
  final VoidCallback onDone;
  final VoidCallback? onSkip;

  @override
  State<RestTimer> createState() => _RestTimerState();
}

class _RestTimerState extends State<RestTimer> {
  /// Seconds left. A notifier rather than a plain field because the sheet a
  /// tap opens shows the same countdown and changes it: two copies of the
  /// number would drift apart by a tick.
  late final ValueNotifier<int> _left = ValueNotifier(
    widget.duration.inSeconds,
  );
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_left.value <= 1) {
        _finish();
        return;
      }
      _left.value--;
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _left.dispose();
    super.dispose();
  }

  /// Stops at zero and reports it once. The ticker is cancelled before the
  /// callback: onDone typically tears this widget down, and a live periodic
  /// timer would then tick into a disposed State. Zero is published first so
  /// an open sheet closes itself before the tag it came from goes.
  void _finish() {
    if (_ticker == null) return;
    _ticker?.cancel();
    _ticker = null;
    _left.value = 0;
    widget.onDone();
  }

  /// ±30s from the sheet: this rest only, never the saved default. Cutting
  /// it to nothing ends it the same way running out does. Capped at the
  /// longest rest Custom allows.
  void _adjust(int seconds) {
    final next = _left.value + seconds;
    if (next <= 0) {
      _finish();
      return;
    }
    _left.value = next > restMaxSeconds ? restMaxSeconds : next;
  }

  void _openSheet() => showRestSheet(
    context,
    countdown: RestCountdown(
      remaining: _left,
      onAdjust: _adjust,
      onSkip: widget.onSkip!,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final tappable = widget.onSkip != null;

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
          Text('REST', style: _tagStyle(t)),
          const SizedBox(width: 5),
          ValueListenableBuilder<int>(
            valueListenable: _left,
            builder: (_, seconds, _) => Text(
              formatRest(seconds),
              key: const Key('rest.remaining'),
              style: _tagStyle(t),
            ),
          ),
          if (tappable) ...[
            const SizedBox(width: 2),
            Icon(
              Icons.expand_more,
              key: const Key('rest.affordance'),
              size: 14,
              color: t.amber,
            ),
          ],
        ],
      ),
    );

    if (!tappable) return tag;
    // The tag opens the rest sheet -- the countdown, ±30s, Skip, and the
    // default for next time. Skip moved in there: one tap cannot both skip
    // and open settings, and skipping by accident while reaching for +30s
    // would be the worse of the two to get wrong.
    return InkWell(
      key: const Key('rest.open'),
      onTap: _openSheet,
      borderRadius: BorderRadius.circular(7),
      child: ConstrainedBox(
        // The tag is drawn small to sit in the bar, but tapped often:
        // Material's 48dp minimum is the target, not the paint.
        constraints: const BoxConstraints(minHeight: 48),
        child: Center(widthFactor: 1, child: tag),
      ),
    );
  }

  TextStyle _tagStyle(FsTokens t) => TextStyle(
    fontFamily: fsMonoFamily,
    fontSize: 10,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.6,
    color: t.amber,
  );
}
