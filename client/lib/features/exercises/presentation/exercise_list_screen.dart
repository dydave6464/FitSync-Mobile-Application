import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import 'exercise_detail_screen.dart';
import 'providers.dart';
import 'widgets/exercise_tile.dart';
import 'widgets/filter_bar.dart';

String describeError(Object error) =>
    error is ApiException ? error.message : 'Something went wrong.';

class ExerciseListScreen extends ConsumerStatefulWidget {
  const ExerciseListScreen({super.key});

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

  @override
  Widget build(BuildContext context) {
    final listing = ref.watch(exerciseListProvider);
    final baseUrl = ref.watch(exerciseRepositoryProvider).baseUrl;

    // A pagination failure is reported without discarding the pages already on
    // screen, so it surfaces as a snack bar rather than an error page.
    ref.listen(listErrorProvider, (_, error) {
      if (error == null) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(describeError(error))));
      ref.read(listErrorProvider.notifier).clear();
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Exercises')),
      body: Column(
        children: [
          const FilterBar(),
          Expanded(
            child: listing.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _ErrorView(
                message: describeError(error),
                onRetry: () => ref.invalidate(exerciseListProvider),
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
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ExerciseDetailScreen(exerciseId: exercise.exerciseId),
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
