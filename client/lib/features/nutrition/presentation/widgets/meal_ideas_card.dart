import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/numbers.dart';
import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../domain/meal_suggestion.dart';
import '../providers.dart';
import 'dish_photo.dart';
import 'meal_idea_rows.dart';

/// The card's two lines, by state (spec 2026-11-13, 1.1).
({String line1, String? line2}) ideasCardLines(MealSuggestions d) {
  final top = d.suggestions.first;
  final plate = '${plateTitle(top)} · ${groupThousands(top.total.kcal.toDouble())} kcal';
  final more = d.suggestions.length - 1;
  return switch (d.state) {
    SuggestionState.fits => (line1: plate, line2: more > 0 ? 'and $more more that fit' : null),
    SuggestionState.noTarget => (line1: plate, line2: 'Add your weight and height to fit these to your day'),
    SuggestionState.reached => (line1: "You've reached today's calories", line2: 'Light options'),
  };
}

/// The card as a screen reader says it, in one breath.
String ideasCardSpoken(MealSuggestions d) {
  final top = d.suggestions.first;
  final plate = [
    top.rice == null ? top.food.name : '${top.food.name} with ${cupsSpoken(top.riceCups)} rice',
    '${top.total.kcal} kilocalories',
  ].join(', ');
  final more = d.suggestions.length - 1;
  final title = 'Suggested for ${d.meal}';
  return switch (d.state) {
    SuggestionState.fits => '$title: $plate${more > 0 ? ', and $more more' : ''}',
    SuggestionState.noTarget => '$title: $plate. Add your weight and height to fit these to your day',
    SuggestionState.reached => "$title: You've reached today's calories. Light options",
  };
}

/// The Nutrition tab's door to Meal ideas: the top plate for the clock's
/// meal and how many more. Brings its own 12 dp above; nothing at all when
/// there is nothing to suggest.
class MealIdeasCard extends ConsumerWidget {
  const MealIdeasCard({super.key, required this.meal, required this.onOpen});

  /// `mealForTime(now)`.
  final String meal;

  /// Null while the tab loads a day: the card shows, faded, and does nothing.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.fs;
    final async = ref.watch(mealSuggestionsProvider(meal));
    // As the page: once an error is attached the old plate is not trusted;
    // a quiet reload (the refetch after a log) keeps it.
    final failed = async.hasError && !async.isLoading;
    final data = async.hasError ? null : async.value;
    if (data != null && data.suggestions.isEmpty) return const SizedBox.shrink();

    final Widget child;
    if (failed) {
      child = SuggestionErrorLine(onRetry: () => ref.invalidate(mealSuggestionsProvider(meal)));
    } else if (data == null) {
      // The first load, or Retry: a card-shaped block, no spinner. An unseen
      // two-line card inside sets its height at any text size, so nothing
      // jumps when the plates come.
      child = Semantics(
        key: const Key('ideas.card.loading'),
        container: true,
        label: 'Loading suggestions',
        excludeSemantics: true,
        child: DecoratedBox(
          decoration: BoxDecoration(color: t.surface2, borderRadius: BorderRadius.circular(FsRadius.md)),
          child: Visibility.maintain(
            visible: false,
            child: _CardFace(title: 'Suggested for $meal', line1: ' ', line2: ' ', onTap: null, keyed: false),
          ),
        ),
      );
    } else {
      final lines = ideasCardLines(data);
      // Faded like Snap a meal above it while the tab loads a day; eased so
      // a quick reload does not flash, at once with reduced motion.
      child = AnimatedOpacity(
        opacity: onOpen == null ? fsDisabledOpacity : 1,
        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 150),
        child: Semantics(
          key: const Key('ideas.card'),
          container: true,
          button: true,
          enabled: onOpen != null,
          label: ideasCardSpoken(data),
          hint: 'Opens meal ideas',
          onTap: onOpen,
          excludeSemantics: true,
          child: _CardFace(
            title: 'Suggested for ${data.meal}',
            // The top plate's dish: in "reached", the top light option.
            photoUrl: data.suggestions.first.food.photoUrl,
            line1: lines.line1,
            line2: lines.line2,
            onTap: onOpen,
          ),
        ),
      );
    }
    return Padding(padding: const EdgeInsets.only(top: 12), child: child);
  }
}

/// The card itself, styled as Snap a meal: the top dish's photo (or the
/// leaf tile), title, one or two lines, chevron.
class _CardFace extends StatelessWidget {
  const _CardFace({
    required this.title,
    this.photoUrl,
    required this.line1,
    required this.line2,
    required this.onTap,
    this.keyed = true,
  });

  final String title;

  /// The top dish's photo; null: the leaf tile.
  final String? photoUrl;
  final String line1;
  final String? line2;
  final VoidCallback? onTap;

  /// False for the placeholder's unseen copy: the line keys are the real card's.
  final bool keyed;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: FsCard(
        small: true,
        onTap: onTap,
        child: Row(
          children: [
            DishPhoto(url: photoUrl, width: 48, height: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: t.text)),
                  const SizedBox(height: 2),
                  Text(line1, key: keyed ? const Key('ideas.card.line1') : null, style: TextStyle(fontSize: 12.5, color: t.text)),
                  if (line2 case final line2?)
                    Text(line2, key: keyed ? const Key('ideas.card.line2') : null, style: TextStyle(fontSize: 12, color: t.text2)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: t.text2),
          ],
        ),
      ),
    );
  }
}
