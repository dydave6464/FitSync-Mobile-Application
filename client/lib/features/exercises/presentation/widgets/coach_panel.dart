import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
import '../../domain/exercise_cues.dart';
import 'ai_cue_list.dart';

/// AI coaching for an exercise that works an injured area, made unmistakable:
/// its own tinted panel, a header naming the injury, a loading state instead
/// of the standard steps silently swapping, and cards that slide in. When the
/// cues cannot be shown, it says why and shows the standard steps. The
/// manuscript asks that AI components stay "discernible".
class CoachPanel extends StatelessWidget {
  const CoachPanel({
    super.key,
    required this.injuryName,
    required this.cues,
    required this.catalogue,
    required this.onRetry,
  });

  final String injuryName;
  final AsyncValue<ExerciseCues> cues;

  /// The exercise's own steps, shown when the request itself failed.
  final ExerciseCues catalogue;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final injury = injuryName.toLowerCase();

    return cues.when(
      loading: () => _Frame(
        key: const Key('coach.loading'),
        tinted: true,
        child: _Loading(injury: injury),
      ),
      error: (_, _) => _Fallback(
        key: const Key('coach.unavailable'),
        message:
            "Couldn't write $injury cues right now. "
            'Here are the standard steps.',
        steps: catalogue,
        onRetry: onRetry,
      ),
      data: (c) {
        if (c.isAi) {
          return _Frame(
            key: const Key('coach.panel'),
            tinted: true,
            child: _Coached(injury: injury, cues: c.cues),
          );
        }
        if (c.notice == 'free_limit') {
          return _Fallback(
            key: const Key('coach.freeLimit'),
            message:
                "You've used today's free AI coaching. Here are the "
                'standard steps. Pro gives AI coaching on every exercise.',
            steps: c,
          );
        }
        if (c.notice == 'unavailable') {
          return _Fallback(
            key: const Key('coach.unavailable'),
            message:
                "Couldn't write $injury cues right now. "
                'Here are the standard steps.',
            steps: c,
            onRetry: onRetry,
          );
        }
        // No longer flagged (e.g. the injury was removed): the plain steps.
        return AiCueList(cues: c);
      },
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({super.key, required this.tinted, required this.child});

  final bool tinted;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FsRadius.card),
        border: Border.all(color: tinted ? t.accentLine : t.line),
        color: tinted ? t.accent.withValues(alpha: 0.08) : t.surface,
      ),
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return Row(
      children: [
        Icon(Icons.auto_awesome, size: 16, color: t.accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: t.text,
            ),
          ),
        ),
      ],
    );
  }
}

class _Loading extends StatefulWidget {
  const _Loading({required this.injury});

  final String injury;

  @override
  State<_Loading> createState() => _LoadingState();
}

class _LoadingState extends State<_Loading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _pulse.value = 1;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header('Writing cues for your ${widget.injury}…'),
        const SizedBox(height: 12),
        for (final width in const [1.0, 0.8, 0.9])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: FadeTransition(
              opacity: Tween(begin: 0.35, end: 0.9).animate(_pulse),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: width,
                child: Container(
                  height: 14,
                  decoration: BoxDecoration(
                    color: t.accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(FsRadius.pill),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Coached extends StatefulWidget {
  const _Coached({required this.injury, required this.cues});

  final String injury;
  final List<Cue> cues;

  @override
  State<_Coached> createState() => _CoachedState();
}

class _CoachedState extends State<_Coached>
    with SingleTickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // "Reduce motion": the cards are simply there.
    if (MediaQuery.of(context).disableAnimations) {
      _reveal.value = 1;
    } else {
      _reveal.forward();
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final n = widget.cues.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header('AI coaching for your ${widget.injury}'),
        const SizedBox(height: 6),
        Text(
          'Written for your ${widget.injury} injury.',
          style: TextStyle(fontSize: 12, color: t.text2),
        ),
        Text(
          'Guidance, not medical advice.',
          style: TextStyle(fontSize: 11.5, color: t.text3),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < n; i++)
          _Staggered(
            controller: _reveal,
            start: n <= 1 ? 0.0 : (i / n) * 0.5,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _CueCard(index: i, cue: widget.cues[i]),
            ),
          ),
      ],
    );
  }
}

class _Staggered extends StatelessWidget {
  const _Staggered({
    required this.controller,
    required this.start,
    required this.child,
  });

  final AnimationController controller;
  final double start;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(
      parent: controller,
      curve: Interval(
        start,
        (start + 0.5).clamp(0.0, 1.0),
        curve: Curves.easeOut,
      ),
    );
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.15),
          end: Offset.zero,
        ).animate(curve),
        child: child,
      ),
    );
  }
}

class _CueCard extends StatelessWidget {
  const _CueCard({required this.index, required this.cue});

  final int index;
  final Cue cue;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(FsRadius.md),
        border: Border.all(color: t.accentLine),
      ),
      child: Padding(
        padding: const EdgeInsets.all(11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${index + 1}',
              style: TextStyle(
                fontFamily: fsMonoFamily,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: t.accent,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cue.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: t.text,
                    ),
                  ),
                  if (cue.detail != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      cue.detail!,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: t.text3,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({
    super.key,
    required this.message,
    required this.steps,
    this.onRetry,
  });

  final String message;
  final ExerciseCues steps;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return _Frame(
      tinted: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 16, color: t.text3),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(fontSize: 12.5, color: t.text2, height: 1.4),
                ),
              ),
            ],
          ),
          if (onRetry != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('coach.retry'),
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ),
          const SizedBox(height: 8),
          AiCueList(
            cues: ExerciseCues.catalogue([for (final c in steps.cues) c.title]),
          ),
        ],
      ),
    );
  }
}
