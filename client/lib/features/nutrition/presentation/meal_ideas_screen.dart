import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../domain/meal_suggestion.dart';
import '../domain/nutrition.dart';
import 'error_snack_bar.dart';
import 'providers.dart';
import 'widgets/log_plate_sheet.dart';
import 'widgets/meal_idea_rows.dart';

/// What the page hands back when a plate was logged from it with its sheet
/// still open: the Nutrition tab says "Logged to lunch" with Undo.
class PlateLogged {
  const PlateLogged(this.meal, this.entries);

  final String meal;
  final List<FoodEntry> entries;
}

/// "Meal ideas": today's local Filipino plates for one meal at a time, the
/// meal picked by its button, three shown at a time up to the server's nine
/// (spec 2026-11-13, 1.2).
class MealIdeasScreen extends ConsumerStatefulWidget {
  const MealIdeasScreen({super.key, required this.initialMeal});

  /// The meal the tab's card was for: the clock's.
  final String initialMeal;

  @override
  ConsumerState<MealIdeasScreen> createState() => _MealIdeasScreenState();
}

class _MealIdeasScreenState extends ConsumerState<MealIdeasScreen> {
  static const _step = 3;

  late String _meal = widget.initialMeal;
  int _shown = _step;

  /// The first row "Show 3 more" brought in, for a screen reader to land on.
  final _firstNew = FocusNode(debugLabel: 'first new idea');

  @override
  void dispose() {
    _firstNew.dispose();
    super.dispose();
  }

  void _pick(String meal) {
    // The meal already picked: keep the plates Show 3 more brought in.
    if (meal == _meal) return;
    setState(() {
      _meal = meal;
      _shown = _step;
    });
  }

  void _more() {
    setState(() => _shown += _step);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _firstNew.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    // Every meal at once, kept while the page is open, so a switch shows
    // the other meal at once.
    for (final m in mealTypes) {
      ref.watch(mealSuggestionsProvider(m));
    }
    final async = ref.watch(mealSuggestionsProvider(_meal));
    // As the tab's card: once an error is attached the old rows are not
    // trusted (a tap could log a plate twice); a quiet reload keeps them.
    final failed = async.hasError && !async.isLoading;
    final data = async.hasError ? null : async.value;

    final Widget body;
    if (failed) {
      body = SuggestionErrorLine(key: ValueKey('error $_meal'), onRetry: () => ref.invalidate(mealSuggestionsProvider(_meal)));
    } else if (data == null) {
      body = const SuggestionPlaceholders(key: ValueKey('loading'));
    } else if (data.suggestions.isEmpty) {
      body = Padding(
        key: ValueKey('empty $_meal'),
        padding: const EdgeInsets.only(top: 4),
        child: Text('Nothing to suggest for $_meal right now.',
            key: const Key('ideas.empty'), style: TextStyle(fontSize: 13, color: t.text2)),
      );
    } else {
      body = _Ideas(
        // Not keyed on _shown: Show 3 more grows the list, it does not
        // cross-fade it; new plates do.
        key: ValueKey('$_meal ${suggestionSignature(data)}'),
        data: data,
        shown: _shown,
        firstNew: _shown > _step ? _shown - _step : null,
        firstNewNode: _firstNew,
        onMore: _more,
        onOpen: (plate) => _open(data, plate),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meal ideas'),
        actions: [
          ExcludeSemantics(child: Icon(Icons.eco_outlined, size: 16, color: t.accentText)),
          const SizedBox(width: 4),
          const FsTag('Local'),
          const SizedBox(width: 16),
        ],
      ),
      body: ListView(
        // 8 of the 12 above the buttons and of the 12 below them sits in
        // their own padding: room for a thumb that lands just off a row.
        // The bottom clears the home indicator once scrolled to the end.
        padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + MediaQuery.paddingOf(context).bottom),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: FsTapRoom(
              // Wraps at large text rather than shrinking a label.
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in mealTypes)
                    FsChip(key: Key('ideas.meal.$m'), label: mealLabel(m), selected: m == _meal, exclusive: true, onTap: () => _pick(m)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          if (MediaQuery.disableAnimationsOf(context))
            body
          else
            // One switcher per meal: within a meal, new rows cross-fade (a
            // log, an edit, a removal); a meal button swaps at once, so the
            // last meal's plates never linger under the new one's.
            AnimatedSwitcher(
              key: ValueKey(_meal),
              duration: const Duration(milliseconds: 200),
              layoutBuilder: (current, previous) =>
                  Stack(alignment: Alignment.topCenter, fit: StackFit.passthrough, children: [...previous, ?current]),
              child: body,
            ),
        ],
      ),
    );
  }

  /// Opens "Log to Lunch" for [plate]. Logged with the sheet still open, the
  /// page closes and the tab says so; dragged away first, the user is still
  /// browsing, so it is said here. "Don't suggest this" is said here too.
  Future<void> _open(MealSuggestions data, MealSuggestion plate) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final screenReader = MediaQuery.accessibleNavigationOf(context);
    final controller = ref.read(nutritionDayProvider.notifier);
    final container = ProviderScope.containerOf(context, listen: false);
    PlateLogged? done;
    await showLogPlateSheet(
      context,
      plate: plate,
      meal: data.meal,
      date: data.date,
      riceFood: data.riceFood,
      usualRiceCups: data.riceCups,
      onLogged: (logged, {required whileOpen}) {
        if (whileOpen) {
          done = PlateLogged(data.meal, logged);
        } else {
          showPlateLoggedSnackBar(messenger, controller, data.meal, logged, screenReader: screenReader);
        }
      },
      onFailedAfterClose: (message) => showErrorSnackBar(messenger, message),
      // Hidden, the page stays: the user is still browsing.
      onHidden: (dish) => showDishHiddenSnackBar(messenger, container, dish, screenReader: screenReader),
    );
    // The sheet's route is gone by now, so this pop is the page's own.
    final result = done;
    if (result != null && mounted) navigator.pop(result);
  }
}

/// The heading line, up to [shown] rows, Show 3 more, and the footnote.
class _Ideas extends StatelessWidget {
  const _Ideas({
    super.key,
    required this.data,
    required this.shown,
    required this.firstNew,
    required this.firstNewNode,
    required this.onMore,
    required this.onOpen,
  });

  final MealSuggestions data;
  final int shown;

  /// The index of the first row the last "Show 3 more" added, if any.
  final int? firstNew;
  final FocusNode firstNewNode;
  final VoidCallback onMore;
  final ValueChanged<MealSuggestion> onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final plates = data.suggestions.take(shown).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(suggestionHeading(data), key: const Key('suggest.subheading'), style: TextStyle(fontSize: 12.5, color: t.text2)),
        const SizedBox(height: 10),
        for (final (i, plate) in plates.indexed) ...[
          if (i > 0) const SizedBox(height: 8),
          PlateRow(
            index: i,
            plate: plate,
            meal: data.meal,
            onTap: () => onOpen(plate),
            focusNode: i == firstNew ? firstNewNode : null,
          ),
        ],
        if (data.suggestions.length > shown) ...[
          const SizedBox(height: 12),
          FsButton(key: const Key('ideas.more'), label: 'Show 3 more', kind: FsButtonKind.secondary, onPressed: onMore),
        ],
        const SizedBox(height: 8),
        Text("Picked by simple rules from your target and today's log.",
            key: const Key('ideas.footnote'), style: TextStyle(fontSize: 12, color: t.text2)),
      ],
    );
  }
}
