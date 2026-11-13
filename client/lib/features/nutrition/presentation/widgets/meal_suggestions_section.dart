import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../domain/meal_suggestion.dart';
import '../error_snack_bar.dart';
import '../providers.dart';
import 'log_plate_sheet.dart';
import 'meal_idea_rows.dart';

/// "Suggested for lunch": up to three local Filipino plates for the meal
/// the clock suggests, fitted by the server to what is left of today (spec
/// 2026-11-09, section 2). The Nutrition tab shows it for today only. It
/// brings its own 16 dp above, and is nothing at all when there is nothing
/// to suggest.
class MealSuggestionsSection extends ConsumerWidget {
  const MealSuggestionsSection({super.key, required this.meal, this.enabled = true});

  /// breakfast, lunch, dinner or snack: `mealForTime(now)`, the Add row the
  /// tab already highlights.
  final String meal;

  /// False while the tab loads a day: the rows stay, but a tap does nothing.
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.fs;
    final async = ref.watch(mealSuggestionsProvider(meal));
    // Riverpod keeps the last value through a reload and through a failure,
    // so the value alone does not say what to show. Once an error is
    // attached the old rows are not trusted: they may hold the plate just
    // logged, and a tap would log it again. A reload without an error (the
    // refetch after a log, an edit or a removal) keeps the rows: no flicker.
    final failed = async.hasError && !async.isLoading;
    final data = async.hasError ? null : async.value;
    // An empty list hides the whole section, heading included.
    if (data != null && data.suggestions.isEmpty) return const SizedBox.shrink();

    final Widget body;
    if (failed) {
      body = SuggestionErrorLine(key: const ValueKey('error'), onRetry: () => ref.invalidate(mealSuggestionsProvider(meal)));
    } else if (data != null) {
      body = _Plates(
        key: ValueKey(suggestionSignature(data)),
        data: data,
        onOpen: enabled ? (plate) => _open(context, ref, data, plate) : null,
      );
    } else {
      // The first load, Retry, or the automatic retries after a failure.
      body = const SuggestionPlaceholders(key: ValueKey('loading'));
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        key: const Key('suggest.section'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            key: const Key('suggest.heading'),
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text('Suggested for $meal', style: Theme.of(context).textTheme.titleMedium),
                ),
              ),
              const SizedBox(width: 8),
              // Beside the tag, not in it: FsTag holds text only.
              ExcludeSemantics(child: Icon(Icons.eco_outlined, size: 16, color: t.accentText)),
              const SizedBox(width: 4),
              const FsTag('Local'),
            ],
          ),
          const SizedBox(height: 4),
          // The rows cross-fade when they change (a log, an edit, a
          // removal); with reduced motion they switch at once.
          if (MediaQuery.disableAnimationsOf(context))
            body
          else
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.topCenter,
                fit: StackFit.passthrough,
                children: [...previous, ?current],
              ),
              child: body,
            ),
        ],
      ),
    );
  }

  /// Opens "Log to Lunch" for [plate]; once both entries are saved, says so
  /// with an Undo that takes them off again -- even when the sheet was
  /// dragged away while saving, as is a failure it can no longer show.
  Future<void> _open(BuildContext context, WidgetRef ref, MealSuggestions data, MealSuggestion plate) async {
    final messenger = ScaffoldMessenger.of(context);
    // Read before the await, while the context is certainly here.
    final screenReader = MediaQuery.accessibleNavigationOf(context);
    final controller = ref.read(nutritionDayProvider.notifier);
    await showLogPlateSheet(
      context,
      plate: plate,
      meal: data.meal,
      date: data.date,
      riceFood: data.riceFood,
      usualRiceCups: data.riceCups,
      onLogged: (logged, {required whileOpen}) =>
          showPlateLoggedSnackBar(messenger, controller, data.meal, logged, screenReader: screenReader),
      onFailedAfterClose: (message) => showErrorSnackBar(messenger, message),
    );
  }
}

/// The heading line, the rows 8 dp apart, and the footnote.
class _Plates extends StatelessWidget {
  const _Plates({super.key, required this.data, required this.onOpen});

  final MealSuggestions data;

  /// Null while the tab is busy: the rows show but do nothing.
  final ValueChanged<MealSuggestion>? onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final open = onOpen;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          suggestionHeading(data),
          key: const Key('suggest.subheading'),
          style: TextStyle(fontSize: 12.5, color: t.text2),
        ),
        const SizedBox(height: 10),
        for (final (i, plate) in data.suggestions.indexed) ...[
          if (i > 0) const SizedBox(height: 8),
          PlateRow(index: i, plate: plate, meal: data.meal, onTap: open == null ? null : () => open(plate)),
        ],
        const SizedBox(height: 8),
        Text(
          "Picked by simple rules from your target and today's log.",
          style: TextStyle(fontSize: 12, color: t.text2),
        ),
      ],
    );
  }
}
