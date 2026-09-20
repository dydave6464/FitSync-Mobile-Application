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
import 'widgets/search_field.dart';

String describeError(Object error) =>
    error is ApiException ? error.message : 'Something went wrong.';

class ExerciseListScreen extends ConsumerStatefulWidget {
  const ExerciseListScreen({super.key, this.selecting = false});

  /// Whether rows are being picked for a workout rather than browsed.
  ///
  /// The Browse tab and the manual-logging picker are the same list over the
  /// same catalogue, filters and pagination; only what a tap means differs.
  /// A second screen would have to copy all of that to change one gesture.
  final bool selecting;

  @override
  ConsumerState<ExerciseListScreen> createState() => _ExerciseListScreenState();
}

class _ExerciseListScreenState extends ConsumerState<ExerciseListScreen> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
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

  @override
  Widget build(BuildContext context) {
    final listing = ref.watch(exerciseListProvider);
    final baseUrl = ref.watch(exerciseRepositoryProvider).baseUrl;
    final draft = widget.selecting
        ? ref.watch(workoutDraftProvider)
        : const <ExerciseSummary>[];

    // A pagination failure is reported without discarding the pages already on
    // screen, so it surfaces as a snack bar rather than an error page.
    ref.listen(listErrorProvider, (_, error) {
      if (error == null) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(describeError(error))));
      ref.read(listErrorProvider.notifier).clear();
    });

    return Scaffold(
      appBar: AppBar(
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
                  return const Center(
                    child: Text('No exercises match those filters.'),
                  );
                }
                return ListView.builder(
                  controller: _controller,
                  itemCount: state.items.length + (state.loadingMore ? 1 : 0),
                  itemBuilder: (context, index) {
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
                          ? () => ref
                                .read(workoutDraftProvider.notifier)
                                .toggle(exercise)
                          : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => ExerciseDetailScreen(
                                  exerciseId: exercise.exerciseId,
                                ),
                              ),
                            ),
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
