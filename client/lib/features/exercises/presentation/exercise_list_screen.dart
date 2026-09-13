import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../sessions/presentation/providers.dart';
import '../../sessions/presentation/session_logger_screen.dart';
import '../../sessions/presentation/workout_draft.dart';
import 'exercise_detail_screen.dart';
import 'providers.dart';
import 'widgets/exercise_tile.dart';
import 'widgets/filter_bar.dart';

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
    final remaining = _controller.position.maxScrollExtent - _controller.position.pixels;
    if (remaining < 400) {
      ref.read(exerciseListProvider.notifier).loadMore();
    }
  }

  /// Guards the start button against a second tap while the first is in
  /// flight -- POST /sessions is idempotent, but a second logger pushed on
  /// top of the first is not something the server can undo.
  bool _starting = false;

  /// Starts the chosen workout and opens the logger on it.
  ///
  /// A session already in progress is reported rather than resumed. The
  /// server is idempotent here: it returns the running session and ignores
  /// the list entirely, so pushing the logger anyway would drop everything
  /// the user just picked and open a workout they did not choose.
  Future<void> _start() async {
    if (_starting) return;
    final draft = ref.read(workoutDraftProvider);
    if (draft.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    if (ref.read(activeSessionProvider).value != null) {
      messenger.showSnackBar(SnackBar(
        content: const Text('You already have a workout in progress.'),
        action: SnackBarAction(
          label: 'Open',
          onPressed: () => navigator.push(MaterialPageRoute<void>(
            builder: (_) => const SessionLoggerScreen(),
          )),
        ),
      ));
      return;
    }

    setState(() => _starting = true);
    try {
      await ref.read(activeSessionProvider.notifier).start(exerciseIds: draft);
      // Cleared only once the session exists. A failed start leaves the picks
      // alone, so the user retries rather than choosing them all again.
      ref.read(workoutDraftProvider.notifier).clear();
      if (!mounted) return;
      await navigator.push(MaterialPageRoute<void>(
        builder: (_) => const SessionLoggerScreen(),
      ));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final listing = ref.watch(exerciseListProvider);
    final baseUrl = ref.watch(exerciseRepositoryProvider).baseUrl;
    final draft = widget.selecting ? ref.watch(workoutDraftProvider) : const <int>[];
    // Watched, not read on demand: reading an unresolved AsyncNotifier hands
    // back null while its first fetch is still in flight, so a session that
    // IS running would look like none at the moment the user taps Start.
    // Only while picking -- the Browse tab has no reason to ask.
    if (widget.selecting) ref.watch(activeSessionProvider);

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
                key: const Key('picker.start'),
                label: draft.length == 1
                    ? 'Start workout · 1 exercise'
                    : 'Start workout · ${draft.length} exercises',
                busy: _starting,
                // A workout of no exercises is not a workout.
                onPressed: draft.isEmpty ? null : _start,
              ),
            ),
      body: Column(
        children: [
          const FilterBar(),
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
                  return const Center(child: Text('No exercises match those filters.'));
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
                          ? draft.contains(exercise.exerciseId)
                          : null,
                      onTap: widget.selecting
                          ? () => ref
                              .read(workoutDraftProvider.notifier)
                              .toggle(exercise.exerciseId)
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
