import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../exercises/presentation/exercise_list_screen.dart' show describeError;
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
  });

  final int planExerciseId;
  final String exerciseName;

  @override
  ConsumerState<ExerciseSwapSheet> createState() => _ExerciseSwapSheetState();
}

class _ExerciseSwapSheetState extends ConsumerState<ExerciseSwapSheet> {
  static const _debounce = Duration(milliseconds: 300);

  final _controller = TextEditingController();
  Timer? _timer;
  String _query = '';
  String? _error;
  bool _busy = false;

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
    try {
      await ref.read(planRepositoryProvider).swap(widget.planExerciseId, alt.exerciseId);
      ref.invalidate(activePlanProvider);
      if (mounted) Navigator.of(context).pop(alt.name);
    } catch (err) {
      // Stay open with the message: closing would throw away the choice they
      // just made, exactly as onboarding stays on a rejected step.
      if (mounted) {
        setState(() {
          _error = describeError(err);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final alternatives = ref.watch(
      alternativesProvider((planExerciseId: widget.planExerciseId, query: _query)),
    );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            Flexible(
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
                            onTap: _busy ? null : () => _choose(alt),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
