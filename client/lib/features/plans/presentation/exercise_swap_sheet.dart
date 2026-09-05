import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../exercises/presentation/equipment_icon.dart';
import '../../exercises/presentation/exercise_list_screen.dart' show describeError;
import '../../exercises/presentation/providers.dart' show exerciseDetailProvider;
import '../domain/exercise_alternative.dart';
import 'providers.dart';

/// Replaces one exercise in the active plan.
///
/// Alternatives lead and the search field starts empty: the catalogue's names
/// are not guessable (one exercise is named `quads`, and the plain bodyweight
/// squat is filed under glutes), so most swaps should need no typing.
class ExerciseSwapSheet extends ConsumerStatefulWidget {
  const ExerciseSwapSheet({
    super.key,
    required this.planExerciseId,
    required this.exerciseName,
    this.onGoToProfile,
  });

  final int planExerciseId;
  final String exerciseName;

  /// Switches the shell to the Profile tab, where equipment is edited.
  ///
  /// Null when the sheet has no shell to drive — it renders the same advice
  /// unlinked rather than offering a link that goes nowhere.
  final VoidCallback? onGoToProfile;

  @override
  ConsumerState<ExerciseSwapSheet> createState() => _ExerciseSwapSheetState();
}

class _ExerciseSwapSheetState extends ConsumerState<ExerciseSwapSheet> {
  static const _debounce = Duration(milliseconds: 300);

  /// How much of the screen the sheet takes, whatever it holds.
  ///
  /// Two thirds is measured rather than guessed: it puts the top edge just
  /// under the plan screen's "Exercises" heading, so the plan stays
  /// recognisable behind the sheet. Sizing to content instead meant a muscle
  /// with a dozen alternatives covered the screen while one with two barely
  /// showed — the same action looking like two different screens.
  static const _heightFraction = 0.66;

  /// Every animation in the catalogue store is 180x180.
  static const _demoSourcePx = 180.0;

  /// How far past its own resolution the demo may be blown up.
  ///
  /// Filling the pane asked for roughly five times the source on a modern
  /// phone, and a renderer given a 180px file and 975px of box has nothing to
  /// put in the gap but interpolation — which is exactly what "blurry" means
  /// here. Three is a compromise: still upscaled, but the demo stays large
  /// enough to read at arm's length. Anything genuinely sharper has to come
  /// from higher-resolution source files, not from this widget.
  static const _maxDemoUpscale = 3.0;

  final _controller = TextEditingController();
  Timer? _timer;
  String _query = '';
  String? _error;
  bool _busy = false;

  /// The candidate being looked at, or null while the list is showing.
  ///
  /// Holding the alternative rather than a bool keeps the list pane's state —
  /// the query, the filter, the scroll offset — untouched underneath, so
  /// backing out of a preview returns to the search that found it.
  ExerciseAlternative? _previewing;

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _timer?.cancel();
    // Debounced so a query does not fire per keystroke.
    _timer = Timer(_debounce, () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  Future<void> _choose(ExerciseAlternative alt) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    // Captured before the await: a completed swap has changed server state,
    // so the plan must be refreshed even if this sheet is dismissed
    // mid-request. Reading `ref` after the await throws once the widget is
    // disposed, and the refresh would be silently lost.
    final container = ProviderScope.containerOf(context, listen: false);

    try {
      await ref.read(planRepositoryProvider).swap(widget.planExerciseId, alt.exerciseId);
      container.invalidate(activePlanProvider);
      // A swap changes which exercises are already in the plan for every
      // row, not just this one — a cached alternatives list for any other
      // row may now be offering the exercise this swap just placed, or
      // hiding the one it just freed up. `invalidate` on a family
      // invalidates every element of it, not one keyed instance.
      container.invalidate(alternativesProvider);
      if (!mounted) return;
      Navigator.of(context).pop(alt.name);
    } catch (err) {
      // Stay open with the message: closing would throw away the choice they
      // just made, exactly as onboarding stays on a rejected step.
      if (!mounted) return;
      setState(() {
        _error = describeError(err);
        _busy = false;
      });
    }
  }

  Future<void> _goToProfile() async {
    final go = widget.onGoToProfile;
    if (go == null) return;
    // Popped first: switching tabs underneath the sheet would leave it
    // covering the screen it just navigated to. `maybePop` rather than `pop`
    // so a sheet rendered as a bare page (as tests do) is a no-op instead of
    // an empty navigator. No value goes back, so the plan screen reads this
    // as "no swap happened" and shows no snackbar.
    await Navigator.of(context).maybePop();
    go();
  }

  /// The way out of a pool the user's equipment has narrowed.
  ///
  /// Outside the `.when` on purpose: the empty state already blames the
  /// equipment filter, but that filter is just as invisible when the list is
  /// full. A cable-machine owner reading three body-weight rows has no way to
  /// tell the pool was narrowed by a setting, so the way out has to be on
  /// screen either way.
  Widget _equipmentHint(FsTokens t) {
    final linked = widget.onGoToProfile != null;
    final note = Text.rich(
      TextSpan(children: [
        const TextSpan(text: "Don't see your equipment? "),
        TextSpan(
          text: 'Update it in Profile \u2192 Equipment & location.',
          style: TextStyle(color: linked ? t.accent : t.text3),
        ),
      ]),
      key: const Key('swap.equipmentHint'),
      style: TextStyle(fontSize: 12, color: t.text3),
    );

    if (!linked) return note;
    // The whole line takes the tap: at 12px the words alone are well under a
    // finger's worth of target.
    return InkWell(
      key: const Key('swap.equipmentHint.link'),
      onTap: _goToProfile,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: note,
      ),
    );
  }

  /// A look at one candidate before it replaces anything.
  ///
  /// The name and equipment come from the row that was tapped, so the pane
  /// can identify itself while the catalogue call is still in flight; only
  /// the demo needs [exerciseDetailProvider].
  Widget _preview(FsTokens t, ExerciseAlternative alt) {
    final theme = Theme.of(context);
    final detail = ref.watch(exerciseDetailProvider(alt.exerciseId));
    final baseUrl = ref.read(planRepositoryProvider).baseUrl;

    return Column(
      key: const Key('swap.preview'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              key: const Key('swap.preview.back'),
              icon: const Icon(Icons.arrow_back, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: _busy ? null : () => setState(() => _previewing = null),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(alt.name, style: theme.textTheme.titleLarge),
                  Text(
                    alt.equipment ?? alt.muscleGroup,
                    style: TextStyle(fontSize: 11.5, color: t.text3),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: detail.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(describeError(err), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FsButton(
                    label: 'Retry',
                    small: true,
                    kind: FsButtonKind.secondary,
                    onPressed: () =>
                        ref.invalidate(exerciseDetailProvider(alt.exerciseId)),
                  ),
                ],
              ),
            ),
            data: (exercise) => exercise.animationUrl == null
                ? Center(
                    child: Text(
                      'No demo for this one yet.',
                      style: TextStyle(color: t.text2),
                    ),
                  )
                : Center(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final side = math.min(
                          _demoSourcePx *
                              _maxDemoUpscale /
                              MediaQuery.devicePixelRatioOf(context),
                          math.min(constraints.maxWidth, constraints.maxHeight),
                        );
                        return SizedBox(
                          width: side,
                          height: side,
                          // Flutter's Image plays animated GIFs natively, as
                          // the catalogue's detail screen already relies on.
                          child: Image.network(
                            '$baseUrl'
                            '${exercise.animationUrl!.startsWith('/') ? '' : '/'}'
                            '${exercise.animationUrl}',
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.medium,
                            errorBuilder: (_, _, _) => Center(
                              child: Icon(equipmentIcon(alt.equipment),
                                  size: 44, color: t.text3),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 12),
        FsButton(
          key: const Key('swap.preview.confirm'),
          label: 'Use this exercise',
          busy: _busy,
          onPressed: () => _choose(alt),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final alternatives = ref.watch(alternativesProvider((
      planExerciseId: widget.planExerciseId,
      query: _query,
    )));

    // The route anchors the sheet to the bottom of the screen and never lifts
    // it for the keyboard — the padding below does that — so the box has to
    // cover the keyboard band it sits behind on top of the height meant to be
    // seen. Without the insets term, focusing the search field would leave
    // only a third of a two-thirds sheet on screen.
    final screen = MediaQuery.sizeOf(context).height;
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    final visible = math.min(screen * _heightFraction, screen - insets);

    final previewing = _previewing;

    return SizedBox(
      height: visible + insets,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 16,
            bottom: insets + 16,
          ),
          // The list pane is replaced rather than covered, so its query, its
          // filter and its scroll offset are all still here when the preview
          // is dismissed.
          child: previewing != null
              ? _preview(t, previewing)
              : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Replace ${widget.exerciseName}',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextField(
                key: const Key('swap.search'),
                controller: _controller,
                onChanged: _onChanged,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search all exercises',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 16),
              Expanded(
                child: alternatives.when(
                  loading: () => const Center(child: Padding(
                    padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
                  error: (err, _) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(describeError(err)),
                  ),
                  data: (rows) => rows.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            _query.isEmpty
                                ? 'Nothing you can do with your equipment trains this muscle.'
                                : 'Nothing you can do matches that search.',
                            style: TextStyle(color: t.text2),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: rows.length,
                          itemBuilder: (_, i) {
                            final alt = rows[i];
                            return ListTile(
                              key: Key('swap.alt.${alt.exerciseId}'),
                              contentPadding: EdgeInsets.zero,
                              title: Text(alt.name),
                              subtitle: Text(alt.equipment ?? alt.muscleGroup),
                              trailing:
                                  Icon(Icons.chevron_right, size: 16, color: t.text3),
                              // Opens a look at it. The swap itself now waits
                              // for the confirm button on the preview: a tap
                              // here used to replace an exercise outright,
                              // before the user had seen what they were
                              // taking on.
                              onTap: _busy
                                  ? null
                                  : () => setState(() => _previewing = alt),
                            );
                          },
                        ),
                ),
              ),
              Divider(color: t.line, height: 25),
              _equipmentHint(t),
            ],
          ),
        ),
      ),
    );
  }
}
