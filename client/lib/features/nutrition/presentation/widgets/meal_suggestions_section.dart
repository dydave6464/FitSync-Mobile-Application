import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../domain/meal_suggestion.dart';
import '../../domain/nutrition.dart' show FoodEntry;
import '../error_snack_bar.dart';
import '../providers.dart';
import 'log_plate_sheet.dart';

/// Changes whenever what the rows show changes, and only then: the key the
/// cross-fade switches on.
String _signature(MealSuggestions data) => [
  data.state.name,
  data.share?.kcal,
  data.share?.proteinG,
  for (final s in data.suggestions) '${s.food.foodId}+${s.rice?.foodId}:${s.total.kcal}',
].join('|');

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
      body = _ErrorLine(key: const ValueKey('error'), onRetry: () => ref.invalidate(mealSuggestionsProvider(meal)));
    } else if (data != null) {
      body = _Plates(
        key: ValueKey(_signature(data)),
        data: data,
        onOpen: enabled ? (plate) => _open(context, ref, data, plate) : null,
      );
    } else {
      // The first load, Retry, or the automatic retries after a failure.
      body = const _Placeholders(key: ValueKey('loading'));
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
      onLogged: (logged) {
        // Replacing, not queueing behind, whatever message is up.
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(SnackBar(
          duration: const Duration(seconds: 4),
          // An action keeps a SnackBar up by default; only a screen reader,
          // which takes longer than four seconds to reach Undo, keeps it here.
          persist: screenReader,
          content: Text('Logged to ${data.meal}'),
          action: SnackBarAction(label: 'Undo', onPressed: () => _undo(messenger, controller, logged)),
        ));
      },
      onFailedAfterClose: (message) => showErrorSnackBar(messenger, message),
    );
  }

  /// Undo deletes both entries, as the meal list's ✕ would.
  static Future<void> _undo(
    ScaffoldMessengerState messenger,
    NutritionDayController controller,
    List<FoodEntry> logged,
  ) async {
    try {
      for (final entry in logged) {
        await controller.remove(entry);
      }
    } catch (_) {
      showErrorSnackBar(messenger, "Couldn't undo. Remove the plate from the meal list.");
    }
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
          _PlateRow(index: i, plate: plate, meal: data.meal, onTap: open == null ? null : () => open(plate)),
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

/// One plate: the whole row is the button. One screen-reader node, its words
/// said once in the label; the + is decoration.
class _PlateRow extends StatelessWidget {
  const _PlateRow({required this.index, required this.plate, required this.meal, required this.onTap});

  final int index;
  final MealSuggestion plate;
  final String meal;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final meta = plateMeta(plate);
    return Semantics(
      key: Key('suggest.row.$index'),
      container: true,
      button: true,
      enabled: onTap != null,
      label: plateSpoken(plate),
      hint: 'Log to $meal',
      onTap: onTap,
      excludeSemantics: true,
      // Faded like a disabled FsButton while the tab loads a day; eased so
      // a quick reload does not flash, at once with reduced motion.
      child: AnimatedOpacity(
        opacity: onTap == null ? fsDisabledOpacity : 1,
        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 150),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: FsCard(
            small: true,
            onTap: onTap,
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plateTitle(plate),
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: t.text),
                      ),
                      const SizedBox(height: 2),
                      Text.rich(
                        TextSpan(
                          style: TextStyle(fontSize: 12, color: t.text2),
                          children: [
                            TextSpan(text: '${meta.lead} · '),
                            // The Protein bar's green, and never without its
                            // number: colour is not the only cue.
                            TextSpan(
                              text: meta.protein,
                              style: TextStyle(color: t.accentText, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        key: Key('suggest.meta.$index'),
                      ),
                      if (plate.highProtein) ...[
                        const SizedBox(height: 6),
                        const FsTag('High protein'),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.add, size: 18, color: t.text2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Three row-shaped blocks where the rows will be, so nothing jumps and no
/// spinner flashes. Said once, as "Loading suggestions".
class _Placeholders extends StatelessWidget {
  const _Placeholders({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return Semantics(
      key: const Key('suggest.loading'),
      container: true,
      label: 'Loading suggestions',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < 3; i++) ...[
            SizedBox(height: i == 0 ? 10 : 8),
            Container(
              key: Key('suggest.placeholder.$i'),
              height: 64,
              decoration: BoxDecoration(color: t.surface2, borderRadius: BorderRadius.circular(FsRadius.md)),
            ),
          ],
        ],
      ),
    );
  }
}

/// One line with Retry; the rest of the tab carries on.
class _ErrorLine extends StatelessWidget {
  const _ErrorLine({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return Row(
      children: [
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Text("Couldn't load suggestions.", style: TextStyle(fontSize: 12.5, color: t.text2)),
          ),
        ),
        TextButton(key: const Key('suggest.retry'), onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}
