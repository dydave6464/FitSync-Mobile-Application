import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme.dart';

/// The countdown between sets, as the mockup's amber app-bar tag.
///
/// It sits in the bar rather than over the content because that is the one
/// place a workout screen has room for it without pushing the set table
/// around every time a set is ticked.
///
/// Client-only and deliberately not persisted: a rest period that elapsed
/// while the app was closed has already elapsed, so restoring one after a
/// force-quit would be theatre.
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
  late int _remaining = widget.duration.inSeconds;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remaining <= 1) {
        // Cancel before the callback: onDone typically tears this widget down,
        // and a live periodic timer would then tick into a disposed State.
        _ticker?.cancel();
        _ticker = null;
        setState(() => _remaining = 0);
        widget.onDone();
        return;
      }
      setState(() => _remaining--);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String get _label {
    final minutes = _remaining ~/ 60;
    final seconds = (_remaining % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    final tag = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: t.amber.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('REST', style: _tagStyle(t)),
          const SizedBox(width: 5),
          Text(_label, key: const Key('rest.remaining'), style: _tagStyle(t)),
        ],
      ),
    );

    // The tag is the skip: the mockup draws no separate control, and a rest
    // timer you cannot cut short is a timer people wait out with their thumb
    // over the screen.
    if (widget.onSkip == null) return tag;
    return InkWell(
      key: const Key('rest.skip'),
      onTap: widget.onSkip,
      borderRadius: BorderRadius.circular(7),
      child: tag,
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
