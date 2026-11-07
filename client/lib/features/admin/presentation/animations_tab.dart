import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/numbers.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../exercises/domain/exercise_labels.dart';
import '../../exercises/presentation/exercise_thumb.dart';
import '../domain/admin_models.dart';
import 'exercise_preview_screen.dart';
import 'providers.dart';
import 'widgets/admin_widgets.dart';
import 'widgets/content_list.dart';

/// The Content tab's Animations segment: the exercise demos, Pending (held
/// back from the library) or Live, searchable by name.
class AnimationsTab extends ConsumerWidget {
  const AnimationsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(adminExercisesQueryProvider);
    final list = ref.watch(adminExercisesProvider);
    // The counts of the last answer, kept while a new list loads.
    final last = list.value?.last;
    String counted(String word, int? count) =>
        count == null ? word : '$word (${groupThousands(count.toDouble())})';
    final baseUrl = ref.watch(adminRepositoryProvider).baseUrl;

    return AdminContentList<AdminExercise>(
      keyPrefix: 'admin.exercises',
      searchHint: 'Search exercises',
      noun: 'exercises',
      query: query,
      chips: [
        (value: 'pending', label: counted('Pending', last?.pendingCount)),
        (value: 'live', label: counted('Live', last?.liveCount)),
      ],
      list: list,
      emptyMessage: query.chip == 'pending'
          ? 'Nothing waiting for review.'
          : 'No live exercises yet.',
      onSearch: ref.read(adminExercisesQueryProvider.notifier).setSearch,
      onChip: ref.read(adminExercisesQueryProvider.notifier).setChip,
      onLoadMore: ref.read(adminExercisesProvider.notifier).loadMore,
      onRetry: () => ref.invalidate(adminExercisesProvider),
      itemBuilder: (context, exercise) => ExerciseRow(
        key: ValueKey('admin.exercise.${exercise.id}'),
        exercise: exercise,
        baseUrl: baseUrl,
        // Pushed over the tabs, so the preview has the whole screen and
        // back returns to the list where it was left.
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ExercisePreviewScreen(exercise: exercise),
          ),
        ),
      ),
    );
  }
}

/// "Hamstrings · Barbell", in the library's words; either part may be
/// missing.
String exerciseSubtitle(AdminExercise exercise) => [
  if (exercise.muscleGroup case final muscle?) muscleLabel(muscle),
  if (exercise.equipment case final equipment?) equipmentLabel(equipment),
].join(' · ');

/// "Live" in the accent, "Pending" in amber: the word is always there, so
/// the colour is never the only clue.
class ExerciseStatusTag extends StatelessWidget {
  const ExerciseStatusTag({super.key, required this.live});

  final bool live;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return live
        ? StatusTag('Live', color: t.accentText)
        : StatusTag('Pending', color: t.amber);
  }
}

class ExerciseRow extends StatelessWidget {
  const ExerciseRow({
    super.key,
    required this.exercise,
    required this.baseUrl,
    this.onTap,
  });

  final AdminExercise exercise;
  final String baseUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final name = exerciseDisplayName(exercise.name);
    final subtitle = exerciseSubtitle(exercise);
    final spoken = [
      name,
      if (subtitle.isNotEmpty) subtitle,
      exercise.live ? 'Live' : 'Pending',
    ].join(', ');

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: FsCard(
        small: true,
        onTap: onTap,
        child: Semantics(
          label: spoken,
          excludeSemantics: true,
          child: Row(
            children: [
              ExerciseThumb(
                size: 48,
                baseUrl: baseUrl,
                thumbnailUrl: exercise.thumbnailUrl,
                equipment: exercise.equipment,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: t.text,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 12, color: t.text2),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ExerciseStatusTag(live: exercise.live),
            ],
          ),
        ),
      ),
    );
  }
}
