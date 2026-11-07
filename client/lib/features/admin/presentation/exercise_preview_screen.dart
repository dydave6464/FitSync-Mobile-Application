import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../exercises/domain/exercise_labels.dart';
import '../../exercises/presentation/equipment_icon.dart';
import '../domain/admin_format.dart';
import '../domain/admin_models.dart';
import 'animations_tab.dart' show ExerciseStatusTag;
import 'providers.dart';

/// One exercise demo, opened from the Animations list: the animation
/// playing, what it trains and with what, why it is pending if it is, and
/// the one thing an admin does to it, publish or unpublish.
class ExercisePreviewScreen extends ConsumerStatefulWidget {
  const ExercisePreviewScreen({super.key, required this.exercise});

  /// The row it was opened from. There is no single-exercise admin route:
  /// the list's answer is the whole of it.
  final AdminExercise exercise;

  @override
  ConsumerState<ExercisePreviewScreen> createState() =>
      _ExercisePreviewScreenState();
}

class _ExercisePreviewScreenState extends ConsumerState<ExercisePreviewScreen> {
  /// The exercise as the last publish or unpublish answered it.
  late AdminExercise _exercise = widget.exercise;
  bool _busy = false;

  String get _name => exerciseDisplayName(_exercise.name);

  Future<void> _publish() => _run(
    () => ref.read(adminRepositoryProvider).publish(_exercise.id),
    done: 'Published. Trainees can now find it in the exercise library.',
  );

  Future<void> _unpublish() async {
    final confirmed = await confirmDestructive(
      context,
      keyPrefix: 'admin.unpublish',
      title: 'Unpublish $_name?',
      message:
          "It leaves the exercise library. Trainees can't get it in new "
          'plans.',
      action: 'Unpublish',
      cancel: 'Keep',
    );
    if (!confirmed || !mounted) return;
    await _run(
      () => ref.read(adminRepositoryProvider).unpublish(_exercise.id),
      done: 'Unpublished.',
    );
  }

  Future<void> _run(
    Future<AdminExercise> Function() call, {
    required String done,
  }) async {
    if (_busy) return;
    // Held from here: the list is refreshed even if this page is left
    // while the call runs, when `ref` can no longer be used.
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _busy = true);
    AdminExercise? changed;
    String message;
    try {
      changed = await call();
      message = done;
    } catch (error) {
      // EXERCISE_IN_USE and EXERCISE_UNCLASSIFIABLE say why, as sent.
      message = userMessage(error);
    }
    // The chips' counts and the rows are out of date after a change; after
    // a failure, the exercise may have been changed by another admin.
    container.invalidate(adminExercisesProvider);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (changed != null) _exercise = changed;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final exercise = _exercise;
    final reason = exercise.live
        ? null
        : switch (exercise.pendingReason) {
            'cardio' => 'Cardio exercise',
            'rare_equipment' => 'Uses rare equipment',
            _ => null,
          };

    // The action stays under the scrolling page, in view whatever the
    // demo's size or the text size, as an editor's Save does.
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _details(exercise, reason)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: exercise.live
                  ? FsButton(
                      key: const Key('admin.exercise.unpublish'),
                      label: 'Unpublish',
                      kind: FsButtonKind.ghost,
                      danger: true,
                      busy: _busy,
                      onPressed: _unpublish,
                    )
                  : FsButton(
                      key: const Key('admin.exercise.publish'),
                      label: 'Publish',
                      busy: _busy,
                      onPressed: _publish,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _details(AdminExercise exercise, String? reason) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
    children: [
      Center(child: _Demo(exercise: exercise)),
      const SizedBox(height: 16),
      Semantics(
        header: true,
        child: Text(_name, style: Theme.of(context).textTheme.titleLarge),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: ExerciseStatusTag(live: exercise.live),
      ),
      const SizedBox(height: 16),
      FsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Fact(
              label: 'Muscle group',
              value: exercise.muscleGroup == null
                  ? 'Not given'
                  : muscleLabel(exercise.muscleGroup!),
            ),
            const SizedBox(height: 10),
            _Fact(
              label: 'Equipment',
              value: exercise.equipment == null
                  ? 'Not given'
                  : equipmentLabel(exercise.equipment!),
            ),
            if (reason != null) ...[
              const SizedBox(height: 10),
              _Fact(label: 'Pending because', value: reason),
            ],
          ],
        ),
      ),
    ],
  );
}

/// The demo GIF, which [Image.network] plays (and holds still under Reduce
/// Motion), in a square no wider than 320 dp: the catalogue's animations are
/// 180 px, and blown up further they only look soft.
class _Demo extends ConsumerWidget {
  const _Demo({required this.exercise});

  final AdminExercise exercise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.fs;
    final baseUrl = ref.watch(adminRepositoryProvider).baseUrl;
    final path = exercise.animationUrl ?? exercise.thumbnailUrl;
    final placeholder = Container(
      color: t.surface2,
      child: Icon(equipmentIcon(exercise.equipment), size: 64, color: t.text3),
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: AspectRatio(
        aspectRatio: 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(FsRadius.md),
          child: path == null
              ? placeholder
              : Image.network(
                  mediaUrl(baseUrl, path),
                  key: const Key('admin.exercise.demo'),
                  fit: BoxFit.cover,
                  semanticLabel:
                      'Demo of ${exerciseDisplayName(exercise.name)}',
                  errorBuilder: (_, _, _) => placeholder,
                ),
        ),
      ),
    );
  }
}

/// A dim label over its value, read as one: "Muscle group, Hamstrings".
class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: t.text3)),
          Text(
            value,
            style: TextStyle(fontSize: 13.5, height: 1.4, color: t.text),
          ),
        ],
      ),
    );
  }
}
