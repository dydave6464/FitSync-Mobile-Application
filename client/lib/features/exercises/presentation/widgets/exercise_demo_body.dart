import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../domain/exercise.dart';
import '../../domain/exercise_cues.dart';
import '../equipment_icon.dart';
import 'ai_cue_list.dart';

/// The animation, chips and "How to perform" list for one exercise.
///
/// Extracted from [ExerciseDetailScreen] (`../exercise_detail_screen.dart`)
/// unchanged, so it can also back the in-session view -- the only things
/// that differ mid-workout are what wraps it (app bar, loading/error
/// branches) and the optional [header] shown above the name.
class ExerciseDemoBody extends StatelessWidget {
  const ExerciseDemoBody({
    super.key,
    required this.exercise,
    this.baseUrl,
    this.header,
    this.cues,
    this.cueSection,
    this.belowChips,
  });

  final ExerciseDetail exercise;
  final String? baseUrl;

  /// Cues to render instead of the catalogue's own. The workout's demo stage
  /// passes the `/cues` answer here, which may have been written for the
  /// user's injury; everything else leaves it null and gets this exercise's
  /// seeded cues.
  final ExerciseCues? cues;

  /// Rendered above the name -- e.g. the in-session position counter and
  /// prescription. Absent on the plain detail screen Train's Exercises tab
  /// opens.
  final Widget? header;

  /// Replaces the cue list entirely. The workout's demo stage passes a
  /// CoachPanel here for an exercise coached for an injury.
  final Widget? cueSection;

  /// Rendered right after the chips and before the cues -- the workout's demo
  /// stage puts its "Switch exercise" link here, next to the name it would
  /// replace. Absent everywhere else.
  final Widget? belowChips;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (exercise.animationUrl != null)
          // Keyed by the animation so a different exercise shown in the same
          // place -- the workout's demo stage after "Switch exercise" -- starts
          // fresh instead of inheriting the last one's play or pause.
          _DemoPlayer(
            key: ValueKey(exercise.animationUrl),
            exercise: exercise,
            baseUrl: baseUrl,
          ),
        const SizedBox(height: 16),
        if (header != null) ...[header!, const SizedBox(height: 8)],
        Text(exercise.name, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            Chip(label: Text(exercise.muscleGroup)),
            if (exercise.equipment != null)
              Chip(label: Text(exercise.equipment!)),
          ],
        ),
        ?belowChips,
        const SizedBox(height: 24),
        // One cue renderer for all three screens that show this body -- the
        // detail Train's Exercises tab opens, the mid-set detour, and the
        // workout's demo stage. Only the last of those ever passes anything in.
        cueSection ??
            AiCueList(cues: cues ?? ExerciseCues.catalogue(exercise.cues)),
        const SizedBox(height: 32),
      ],
    );
  }
}

/// The exercise's animation, which the viewer can pause, and which waits for
/// a tap under Reduce Motion.
///
/// The GIF is paused with [TickerMode] rather than by swapping in the still:
/// [Image] stops listening to its frame stream while tickers are disabled, so
/// turning them off freezes the frame on screen -- the pose the viewer
/// stopped on is the one they wanted to look at.
///
/// [Image] also stops for an inherited Reduce Motion
/// ([MediaQuery.disableAnimationsOf]), which [TickerMode] cannot override. So
/// the GIF sits under a [MediaQuery] that lifts it, leaving [TickerMode] -- and
/// through it the viewer's tap -- as the only thing that decides.
class _DemoPlayer extends StatefulWidget {
  const _DemoPlayer({super.key, required this.exercise, required this.baseUrl});

  final ExerciseDetail exercise;
  final String? baseUrl;

  /// Every animation in the catalogue store is 180x180.
  static const _sourcePx = 180.0;

  /// How far past its own resolution the demo may be blown up. Filling a
  /// tablet's width asked for six times the source and looked soft for it;
  /// three matches the cap the swap sheet's preview already settled on.
  static const _maxUpscale = 3.0;

  @override
  State<_DemoPlayer> createState() => _DemoPlayerState();
}

class _DemoPlayerState extends State<_DemoPlayer> {
  /// The viewer's own choice, once they have tapped. Until then the demo
  /// follows Reduce Motion, so turning it on mid-screen still holds it.
  bool? _chosenPlaying;

  /// Whether the animation has been on screen at all. Before that, Reduce
  /// Motion shows the still thumbnail; after, a pause keeps the GIF's frame.
  bool _started = false;

  void _toggle(bool playing) => setState(() {
    _chosenPlaying = !playing;
    _started = true;
  });

  Widget _fallback() =>
      Center(child: Icon(equipmentIcon(widget.exercise.equipment), size: 48));

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final playing = _chosenPlaying ?? !MediaQuery.disableAnimationsOf(context);
    final thumb = widget.exercise.thumbnailUrl;
    final still = thumb == null
        ? null
        : Image.network(
            '${widget.baseUrl}$thumb',
            fit: BoxFit.contain,
            // flutter_lints (this SDK) flags __/___ as unnecessary now that
            // repeated `_` is a valid wildcard for each parameter.
            errorBuilder: (_, _, _) => _fallback(),
          );

    final Widget picture;
    if (!playing && !_started && still != null) {
      picture = still;
    } else {
      // Reduce Motion has already been honoured above: [playing] starts false
      // under it and only a tap turns it on. Left inherited, it would keep
      // the GIF on its first frame even after that tap.
      picture = MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: false),
        child: TickerMode(
          enabled: playing,
          // Flutter's Image plays animated GIFs natively -- no package.
          child: Image.network(
            '${widget.baseUrl}${widget.exercise.animationUrl}',
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            // Until the first frame lands, the still stands in, so the box is
            // never blank while a slow connection fetches the whole GIF.
            frameBuilder: (_, child, frame, wasSynchronouslyLoaded) =>
                frame == null && !wasSynchronouslyLoaded
                ? (still ?? child)
                : child,
            errorBuilder: (_, _, _) => _fallback(),
          ),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: _DemoPlayer._sourcePx * _DemoPlayer._maxUpscale,
        ),
        child: AspectRatio(
          aspectRatio: 1,
          child: Semantics(
            button: true,
            label: playing ? 'Pause demo' : 'Play demo',
            excludeSemantics: true,
            onTap: () => _toggle(playing),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _toggle(playing),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  picture,
                  if (!playing)
                    Center(
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: t.bg.withValues(alpha: 0.72),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.play_arrow_rounded,
                          size: 40,
                          color: t.text,
                        ),
                      ),
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
