import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/widgets/fs_kit.dart';
import '../domain/exercise.dart';
import '../../sessions/presentation/workout_draft.dart';
import '../../sessions/presentation/workout_review_screen.dart';
import 'exercise_detail_screen.dart';
import 'providers.dart';
import 'widgets/exercise_tile.dart';
import 'widgets/equipment_filter_button.dart';
import 'widgets/recent_strip.dart';
import 'widgets/region_filter_bar.dart';
import 'widgets/search_field.dart';

String describeError(Object error) =>
    error is ApiException ? error.message : 'Something went wrong.';

class ExerciseListScreen extends ConsumerStatefulWidget {
  const ExerciseListScreen({
    super.key,
    this.selecting = false,
    this.embedded = false,
  });

  /// Whether rows are being picked for a workout rather than browsed.
  ///
  /// Train's Exercises tab and the manual-logging picker are the same list
  /// over the same catalogue, filters and pagination; only what a tap means
  /// differs. A second screen would have to copy all of that to change one
  /// gesture.
  final bool selecting;

  /// Hosted inside Train's tab body, under Train's own header: no AppBar,
  /// or the screen would carry two titles.
  final bool embedded;

  @override
  ConsumerState<ExerciseListScreen> createState() => _ExerciseListScreenState();
}

class _ExerciseListScreenState extends ConsumerState<ExerciseListScreen> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    // Train's Exercises tab stays mounted once opened and keeps listening to
    // the recent list, so autoDispose alone never lets it go. A picker is
    // opened to log a workout, and one logged since the tab first asked is
    // exactly what its strip should show, so it asks again on every open.
    // After the first frame, because initState runs while the route is being
    // built, and invalidating then would rebuild the tab mid-build.
    if (widget.selecting) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.invalidate(recentExercisesProvider);
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final remaining =
        _controller.position.maxScrollExtent - _controller.position.pixels;
    if (remaining < 400) {
      ref.read(exerciseListProvider.notifier).loadMore();
    }
  }

  /// Opens the last look at the workout before it becomes a session.
  ///
  /// Pushed rather than replacing this route: "Add more exercises" on the
  /// review screen pops straight back to the library, with the picks and the
  /// scroll position the user left behind.
  void _review() => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const WorkoutReviewScreen()));

  void _open(ExerciseSummary exercise) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ExerciseDetailScreen(exerciseId: exercise.exerciseId),
    ),
  );

  void _toggle(ExerciseSummary exercise) =>
      ref.read(workoutDraftProvider.notifier).toggle(exercise);

  @override
  Widget build(BuildContext context) {
    final listing = ref.watch(exerciseListProvider);
    final baseUrl = ref.watch(exerciseRepositoryProvider).baseUrl;
    final draft = widget.selecting
        ? ref.watch(workoutDraftProvider)
        : const <ExerciseSummary>[];
    final filters = ref.watch(selectedFiltersProvider);

    // Recent work is a shortcut for the unfiltered library only. Under a
    // search, an area or a piece of gear, the user has asked a question, and
    // a strip that ignored it would sit on top of the answer.
    final showRecent =
        filters.isEmpty && ref.watch(catalogueConstraintProvider).isEmpty;
    // Held for as long as the library is open, not just while the strip is
    // built: it is the list's first row, and scrolling it out of view would
    // otherwise drop the answer and refetch it -- the strip blinking out and
    // the list jumping -- on the way back up.
    ref.watch(recentExercisesProvider);
    final recent = showRecent
        ? RecentStrip(
            baseUrl: baseUrl,
            onTap: widget.selecting ? _toggle : _open,
            isAdded: widget.selecting
                ? (exercise) => draft.holds(exercise.exerciseId)
                : null,
          )
        : null;

    // A pagination failure is reported without discarding the pages already on
    // screen, so it surfaces as a snack bar rather than an error page.
    ref.listen(listErrorProvider, (_, error) {
      if (error == null) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(describeError(error))));
      ref.read(listErrorProvider.notifier).clear();
    });

    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: Text(widget.selecting ? 'Exercise library' : 'Exercises'),
              actions: [
                if (widget.selecting)
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Center(child: FsTag('${draft.length} added')),
                  ),
              ],
            ),
      bottomNavigationBar: !widget.selecting
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: FsButton(
                key: const Key('picker.review'),
                label: draft.length == 1
                    ? 'Review · 1 exercise'
                    : 'Review · ${draft.length} exercises',
                // A workout of no exercises is not a workout.
                onPressed: draft.isEmpty ? null : _review,
              ),
            ),
      body: Column(
        children: [
          // Above the equipment button, because it is the wider net: the
          // button narrows the catalogue to one kind of gear, the box finds
          // one movement by name.
          const ExerciseSearchField(),
          // Under the box and above the equipment, as the design draws it:
          // the area is the first thing a person narrows a session by.
          const RegionFilterBar(),
          const EquipmentFilterButton(),
          Expanded(
            child: listing.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _ErrorView(
                message: describeError(error),
                // Both, not just the list. An outage takes the filter bar
                // down too, and its own error branch renders an empty strip
                // with no way back — so a retry that recovered only the list
                // would leave filtering silently dead until an app restart.
                onRetry: () {
                  ref.invalidate(exerciseListProvider);
                  ref.invalidate(exerciseFiltersProvider);
                },
              ),
              data: (state) {
                if (state.items.isEmpty) {
                  return _EmptyView(
                    // Only the chips: the search box carries its own clear
                    // button, and the term is still on screen above.
                    onClear: filters.hasChipFilter
                        ? ref.read(selectedFiltersProvider.notifier).clear
                        : null,
                  );
                }
                // The strip rides at the top of the list rather than above
                // it, so it scrolls away with the rows instead of holding
                // part of a small screen for good.
                final lead = recent == null ? 0 : 1;
                return ListView.builder(
                  controller: _controller,
                  itemCount:
                      lead + state.items.length + (state.loadingMore ? 1 : 0),
                  itemBuilder: (context, position) {
                    if (position < lead) return recent;
                    final index = position - lead;
                    if (index >= state.items.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final exercise = state.items[index];
                    return ExerciseTile(
                      exercise: exercise,
                      baseUrl: baseUrl,
                      selected: widget.selecting
                          ? draft.holds(exercise.exerciseId)
                          : null,
                      onTap: widget.selecting
                          ? () => _toggle(exercise)
                          : () => _open(exercise),
                      // Picking took the row's tap, so the demo needs a
                      // button of its own: choosing an exercise is easier
                      // once you have seen what it is.
                      onInfo: widget.selecting ? () => _open(exercise) : null,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.onClear});

  /// Null when no chip is lit, so there is nothing for the button to clear.
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'No exercises match those filters.',
            textAlign: TextAlign.center,
          ),
          if (onClear != null) ...[
            const SizedBox(height: 8),
            TextButton(
              key: const Key('library.clearFilters'),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: onClear,
              child: const Text('Clear filters'),
            ),
          ],
        ],
      ),
    ),
  );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 40),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}
