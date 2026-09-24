import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/units.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../exercises/presentation/exercise_list_screen.dart'
    show describeError;
import '../../profile/presentation/providers.dart' show weightUnitProvider;
import '../domain/streaks.dart';
import 'providers.dart';

/// Adds a lift goal in two steps: choose the exercise, then the target.
/// Closes on a save that lands; stays open, saying why, on one that does not.
Future<void> showAddGoalSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.fs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    isScrollControlled: true,
    builder: (_) => const _AddGoalSheet(),
  );
}

/// The exercise chosen in step one, with the user's best when known.
typedef _Picked = ({int exerciseId, String name, double? bestKg});

class _AddGoalSheet extends ConsumerStatefulWidget {
  const _AddGoalSheet();

  @override
  ConsumerState<_AddGoalSheet> createState() => _AddGoalSheetState();
}

class _AddGoalSheetState extends ConsumerState<_AddGoalSheet> {
  final _search = TextEditingController();
  final _target = TextEditingController();
  Timer? _debounce;
  String _query = '';
  _Picked? _picked;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _target.dispose();
    super.dispose();
  }

  /// The same 300 ms wait as Browse's search, so each keystroke is not a
  /// request.
  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  /// A catalogue result carries no best of the user's; the lifted-before
  /// list does, so a lift found by search still gets it.
  void _pick(int exerciseId, String name, List<GoalOption> known) {
    double? best;
    for (final o in known) {
      if (o.exerciseId == exerciseId) best = o.bestKg;
    }
    setState(() {
      _picked = (exerciseId: exerciseId, name: name, bestKg: best);
      _error = null;
    });
  }

  Future<void> _save() async {
    final picked = _picked!;
    final unit = ref.read(weightUnitProvider);
    // Capture the container before any await; the sheet can be dismissed
    // mid-save, making ref invalid. The container outlives the widget.
    final container = ProviderScope.containerOf(context, listen: false);
    final kg = parseWeight(_target.text, unit);
    if (kg == null || kg <= 0) {
      setState(() => _error = 'Enter a target weight.');
      return;
    }
    final best = picked.bestKg;
    if (best != null && kg <= best) {
      setState(
        () => _error =
            'Your best is already ${formatWeightWithUnit(best, unit)}.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(goalsRepositoryProvider)
          .add(
            exerciseId: picked.exerciseId,
            targetKg: double.parse(kg.toStringAsFixed(2)),
          );
      container.invalidate(goalsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watched here, whichever step is showing, so the list is still loaded
    // when a search result needs its best.
    final options = ref.watch(goalOptionsProvider);
    final picked = _picked;
    final media = MediaQuery.of(context);
    // Calculate the space left above the keyboard, accounting for app bar
    // and padding. This ensures the sheet fits and the target field stays on screen.
    final roomAboveKeyboard =
        media.size.height -
        media.viewInsets.bottom -
        media.padding.top -
        56; // Approximate app bar height
    final height = math.max(
      160.0,
      math.min(media.size.height * 0.7, roomAboveKeyboard),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + media.viewInsets.bottom),
      child: SizedBox(
        height: height,
        child: picked == null ? _chooseStep(options) : _targetStep(picked),
      ),
    );
  }

  Widget _chooseStep(AsyncValue<List<GoalOption>> options) {
    final t = context.fs;
    final known = options.value ?? const <GoalOption>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'New goal',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: t.text,
          ),
        ),
        const SizedBox(height: 12),
        FsField(
          controller: _search,
          hint: 'Search exercises',
          fieldKey: const Key('goal.search'),
          icon: Icons.search,
          onChanged: _onSearch,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _query.isEmpty
              ? _liftedBefore(options)
              : _searchResults(known),
        ),
      ],
    );
  }

  Widget _liftedBefore(AsyncValue<List<GoalOption>> options) {
    final unit = ref.watch(weightUnitProvider);
    return options.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _Hint(describeError(error)),
      data: (list) => list.isEmpty
          ? const _Hint('Search for an exercise to set a goal.')
          : ListView(
              children: [
                const FsEyebrow('Lifted before'),
                const SizedBox(height: 4),
                for (final o in list)
                  _PickRow(
                    key: Key('goal.option.${o.exerciseId}'),
                    title: o.name,
                    subtitle: 'Best ${formatWeightWithUnit(o.bestKg, unit)}',
                    onTap: () => _pick(o.exerciseId, o.name, list),
                  ),
              ],
            ),
    );
  }

  Widget _searchResults(List<GoalOption> known) {
    return ref
        .watch(goalSearchProvider(_query))
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _Hint(describeError(error)),
          data: (items) => items.isEmpty
              ? _Hint('No exercises match "$_query".')
              : ListView(
                  children: [
                    for (final e in items)
                      _PickRow(
                        key: Key('goal.result.${e.exerciseId}'),
                        title: e.name,
                        subtitle: null,
                        onTap: () => _pick(e.exerciseId, e.name, known),
                      ),
                  ],
                ),
        );
  }

  Widget _targetStep(_Picked picked) {
    final t = context.fs;
    final unit = ref.watch(weightUnitProvider);
    final best = picked.bestKg;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                key: const Key('goal.back'),
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back),
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _picked = null;
                        _error = null;
                      }),
              ),
              Expanded(
                child: Text(
                  picked.name,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            best == null
                ? 'Not logged yet'
                : 'Your best: ${formatWeightWithUnit(best, unit)}',
            style: TextStyle(fontSize: 13, color: t.text2),
          ),
          const SizedBox(height: 16),
          FsField(
            controller: _target,
            hint: 'Target (${unit.api})',
            fieldKey: const Key('goal.target'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              key: const Key('goal.error'),
              style: TextStyle(fontSize: 13, color: t.red),
            ),
          ],
          const SizedBox(height: 16),
          FsButton(
            key: const Key('goal.save'),
            label: 'Save goal',
            busy: _busy,
            onPressed: _busy ? null : _save,
          ),
        ],
      ),
    );
  }
}

class _PickRow extends StatelessWidget {
  const _PickRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: t.text,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!, style: TextStyle(fontSize: 11.5, color: t.text3)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: context.fs.text2),
        ),
      ),
    );
  }
}
