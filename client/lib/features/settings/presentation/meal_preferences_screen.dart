import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../nutrition/domain/meal_suggestion.dart';
import '../../nutrition/presentation/providers.dart'
    show
        hiddenSuggestionsProvider,
        mealSuggestionsProvider,
        nutritionRepositoryProvider;
import '../../profile/presentation/providers.dart';

/// Meal preferences: the rice suggested plates carry, the foods suggestions
/// skip and the dishes the user hid, each saved on tap (spec 2026-11-13,
/// round 2, 1.3). Opened from Settings and from the Meal ideas page.
class MealPreferencesScreen extends ConsumerStatefulWidget {
  const MealPreferencesScreen({super.key});

  @override
  ConsumerState<MealPreferencesScreen> createState() =>
      _MealPreferencesScreenState();
}

class _MealPreferencesScreenState extends ConsumerState<MealPreferencesScreen> {
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Meal preferences')),
    body: ListView(
      // The bottom clears the home indicator once scrolled to the end.
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: const [
        _Heading('Rice with meals'),
        _RiceSection(),
        SizedBox(height: 20),
        _Heading('Foods I avoid'),
        _AvoidSection(),
        SizedBox(height: 20),
        _Heading('Dishes you hid'),
        _HiddenSection(),
      ],
    ),
  );
}

/// A section's heading, announced as one, as the admin food form's are.
/// Two lines at most rather than cut short at large text.
class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 10),
    child: Semantics(header: true, child: FsEyebrow(text, maxLines: 2)),
  );
}

/// The line under a section's chips.
class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(fontSize: 12.5, color: context.fs.text2));
}

/// The cups of rice suggested plates carry: round 1's Rice with meals sheet,
/// moved here.
class _RiceSection extends ConsumerStatefulWidget {
  const _RiceSection();

  @override
  ConsumerState<_RiceSection> createState() => _RiceSectionState();
}

class _RiceSectionState extends ConsumerState<_RiceSection> {
  /// The amount on its way to the server, drawn in place of the saved one.
  double? _pending;

  /// Set when the last save was refused; cleared by the next tap.
  bool _failed = false;

  /// Saves as the Weight unit switch does: the new amount shows at once,
  /// further taps wait for the answer, and a refused save goes back and says
  /// so. `ProfileNotifier.patch` refetches the suggestions itself.
  Future<void> _save(double cups) async {
    if (_pending != null) return;
    setState(() {
      _pending = cups;
      _failed = false;
    });
    // Captured before the await: the screen can be closed while the save
    // runs, and the app-level messenger outlives it.
    final messenger = ScaffoldMessenger.of(context);
    final route = ModalRoute.of(context);
    try {
      await ref.read(profileProvider.notifier).patch({'usualRiceCups': cups});
    } catch (error) {
      // The screen says only that it failed; anything the API layer did not
      // name is logged for why.
      if (error is! ApiException) {
        debugPrint('Saving $cups cups of rice failed: $error');
      }
      // On the screen while it is open; once it is closing or closed, as a
      // snack bar on the page under it, so the failure is never silent.
      if (mounted && (route?.isCurrent ?? false)) {
        setState(() => _failed = true);
      } else {
        messenger.showSnackBar(
          const SnackBar(content: Text("Couldn't save your rice. Try again.")),
        );
      }
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(profileProvider).value?.usualRiceCups ?? 1;
    final shown = _pending ?? saved;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Wraps at large text rather than shrinking a label. FsTapRoom lets
        // each chip's 48 dp band reach past the row, as on the Log sheet's
        // rice line.
        FsTapRoom(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final cups in riceChoices)
                FsChip(
                  key: Key('prefs.rice.$cups'),
                  label: cups == 0 ? 'None' : cupsLabel(cups),
                  selected: shown == cups,
                  exclusive: true,
                  onTap: _pending == null ? () => _save(cups) : null,
                ),
            ],
          ),
        ),
        // FsTapRoom's reach below the row: room inside the column, which
        // hit-tests only its own box, not the padding around it.
        const SizedBox(height: 8),
        // FsErrorLine is a live region, so it is read out.
        if (_failed) ...[
          const FsErrorLine(
            "Couldn't save your rice. Try again.",
            key: Key('prefs.riceError'),
          ),
          const SizedBox(height: 8),
        ],
        const _Note(
          'Used for suggested plates. You can change it when you log a plate.',
        ),
      ],
    );
  }
}

/// The food groups suggestions skip. Each tap saves the whole new set, so
/// two quick taps can never save half a choice.
class _AvoidSection extends ConsumerStatefulWidget {
  const _AvoidSection();

  @override
  ConsumerState<_AvoidSection> createState() => _AvoidSectionState();
}

class _AvoidSectionState extends ConsumerState<_AvoidSection> {
  /// The set on its way to the server, drawn in place of the saved one.
  List<String>? _pending;

  /// Set when the last save was refused; cleared by the next tap.
  bool _failed = false;

  Future<void> _toggle(List<String> saved, String group) async {
    if (_pending != null) return;
    final on = saved.contains(group);
    // In the fixed order, whatever order they were tapped in.
    final next = [
      for (final g in foodGroups)
        if (g == group ? !on : saved.contains(g)) g,
    ];
    setState(() {
      _pending = next;
      _failed = false;
    });
    try {
      // Refetches the suggestions itself.
      await ref.read(profileProvider.notifier).patch({'avoidFoods': next});
    } catch (error) {
      if (error is! ApiException) {
        debugPrint('Saving foods to avoid $next failed: $error');
      }
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(profileProvider).value?.avoidFoods ?? const [];
    final shown = _pending ?? saved;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Wraps at large text; each chip's 48 dp band reaches past the row.
        FsTapRoom(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final g in foodGroups)
                FsChip(
                  key: Key('prefs.avoid.$g'),
                  label: foodGroupLabel(g),
                  selected: shown.contains(g),
                  onTap: _pending == null ? () => _toggle(saved, g) : null,
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (_failed) ...[
          const FsErrorLine(
            "Couldn't save. Try again.",
            key: Key('prefs.avoidError'),
          ),
          const SizedBox(height: 8),
        ],
        const _Note('Suggestions skip dishes often made with these.'),
        const SizedBox(height: 4),
        const _Note('Recipes vary — check ingredients if you have an allergy.'),
      ],
    );
  }
}

/// The dishes the user asked not to be suggested, newest first, each with
/// Show again.
class _HiddenSection extends ConsumerStatefulWidget {
  const _HiddenSection();

  @override
  ConsumerState<_HiddenSection> createState() => _HiddenSectionState();
}

class _HiddenSectionState extends ConsumerState<_HiddenSection> {
  /// The rows whose Show again is on its way.
  final Set<int> _showing = {};

  /// Shown again: off the list at once, before the refetch answers.
  final Set<int> _gone = {};

  /// A refused Show again, said under its row; cleared by its next tap.
  final Map<int, String> _errors = {};

  Future<void> _show(int foodId, String name) async {
    if (_showing.contains(foodId)) return;
    setState(() {
      _showing.add(foodId);
      _errors.remove(foodId);
    });
    // Captured before the await: the screen can be closed meanwhile.
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await ref.read(nutritionRepositoryProvider).showSuggestion(foodId);
    } catch (error) {
      if (error is! ApiException) {
        debugPrint('Showing food $foodId again failed: $error');
      }
      if (mounted) {
        setState(() {
          _showing.remove(foodId);
          _errors[foodId] = "Couldn't show $name again. Try again.";
        });
      }
      return;
    }
    container
      ..invalidate(hiddenSuggestionsProvider)
      ..invalidate(mealSuggestionsProvider);
    if (mounted) {
      setState(() {
        _showing.remove(foodId);
        _gone.add(foodId);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final async = ref.watch(hiddenSuggestionsProvider);
    if (async.hasError && !async.isLoading) {
      return FsRetry(
        message: userMessage(async.error!),
        onRetry: () => ref.invalidate(hiddenSuggestionsProvider),
      );
    }
    final hidden = async.hasError ? null : async.value;
    if (hidden == null) {
      return Semantics(
        container: true,
        label: 'Loading hidden dishes',
        excludeSemantics: true,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: t.surface2,
            borderRadius: BorderRadius.circular(FsRadius.md),
          ),
        ),
      );
    }
    final rows = [
      for (final h in hidden)
        if (!_gone.contains(h.foodId)) h,
    ];
    if (rows.isEmpty) {
      return Text(
        'No hidden dishes. Use "Don\'t suggest this" on a plate to hide one.',
        key: const Key('prefs.hiddenEmpty'),
        style: TextStyle(fontSize: 13, color: t.text2),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final h in rows)
          Column(
            key: Key('prefs.hidden.${h.foodId}'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The button takes at most half the row, its words wrapping
              // at large text, so the name always keeps room to wrap too.
              LayoutBuilder(
                builder: (context, box) => Row(
                  children: [
                    Expanded(
                      child: Text(
                        h.name,
                        style: TextStyle(fontSize: 14, color: t.text),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: box.maxWidth / 2),
                      child: _ShowAgainButton(
                        foodId: h.foodId,
                        name: h.name,
                        busy: _showing.contains(h.foodId),
                        onPressed: () => _show(h.foodId, h.name),
                      ),
                    ),
                  ],
                ),
              ),
              if (_errors[h.foodId] case final message?) ...[
                FsErrorLine(message, key: Key('prefs.hiddenError.${h.foodId}')),
                const SizedBox(height: 8),
              ],
            ],
          ),
      ],
    );
  }
}

/// "Show again", the dish named for a screen reader; a spinner while busy.
class _ShowAgainButton extends StatelessWidget {
  const _ShowAgainButton({
    required this.foodId,
    required this.name,
    required this.busy,
    required this.onPressed,
  });

  final int foodId;
  final String name;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // excludeSemantics drops the button's own state, so it is restated here.
    return Semantics(
      label: 'Show $name again',
      button: true,
      enabled: !busy,
      onTap: busy ? null : onPressed,
      excludeSemantics: true,
      child: TextButton(
        key: Key('prefs.show.$foodId'),
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
        onPressed: busy ? null : onPressed,
        child: busy
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Show again'),
      ),
    );
  }
}
