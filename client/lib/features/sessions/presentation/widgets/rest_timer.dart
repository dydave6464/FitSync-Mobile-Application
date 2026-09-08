import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme.dart';

/// The countdown between sets.
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: t.amber.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(FsRadius.md),
        border: Border.all(color: t.amber.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.timer_outlined, size: 17, color: t.amber),
          const SizedBox(width: 9),
          Text(
            'Rest',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: t.text),
          ),
          const Spacer(),
          Text(
            _label,
            key: const Key('rest.remaining'),
            style: TextStyle(
              fontFamily: fsMonoFamily,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: t.amber,
            ),
          ),
          if (widget.onSkip != null) ...[
            const SizedBox(width: 12),
            TextButton(
              key: const Key('rest.skip'),
              onPressed: widget.onSkip,
              child: const Text('Skip'),
            ),
          ],
        ],
      ),
    );
  }
}
