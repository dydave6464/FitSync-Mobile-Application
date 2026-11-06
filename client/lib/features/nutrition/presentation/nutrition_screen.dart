import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/client_id.dart';
import '../../../core/manila_day.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../domain/nutrition.dart';
import 'error_snack_bar.dart';
import 'log_food_screen.dart';
import 'meal_photo/snap_meal.dart';
import 'providers.dart';
import 'widgets/fatsecret_attribution.dart';
import 'widgets/log_food_sheet.dart';
import 'widgets/meal_section.dart';
import 'widgets/nutrition_summary_card.dart';

class NutritionScreen extends ConsumerWidget {
  const NutritionScreen({super.key, this.onGoToProfile});

  final VoidCallback? onGoToProfile;

  void _openLog(BuildContext context, WidgetRef ref, String mealType) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => LogFoodScreen(
      mealType: mealType,
      onLogged: (entry, date) => _offerChange(context, ref, entry, date),
    )),
  );

  /// Snap a meal from the tab, on the day shown: today with the meal the
  /// clock suggests; on a past day the clock says nothing, so with no meal
  /// picked. "Search instead" swaps the photo screen for Log food, which
  /// always opens on a meal -- the one picked, or else [fallback].
  Future<void> _snap(BuildContext context, WidgetRef ref, String? mealType, String fallback, String date) =>
      startSnapMeal(
        context,
        ref,
        mealType: mealType,
        date: date,
        onSearchInstead: (photoContext, meal) => Navigator.of(photoContext).pushReplacement(MaterialPageRoute<void>(
          builder: (_) =>
              LogFoodScreen(mealType: meal ?? fallback, onLogged: (entry, d) => _offerChange(context, ref, entry, d)),
        )),
      );

  /// The one way a logged food is changed, from its row or from "Added …
  /// · Change". [context] is this screen's: still mounted and under the
  /// app's Navigator after Log food has closed. [date] is the entry's own
  /// day, which may no longer be the one on screen.
  Future<void> _change(BuildContext context, WidgetRef ref, FoodEntry entry, String? date) async {
    final choice = await showLogFoodSheet(context, entry.asFood(),
        mealType: entry.mealType, servings: entry.servings, changing: true);
    if (choice == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(nutritionDayProvider.notifier);
    // Try again sends the same change: the sheet's choices are not lost.
    await saveOrOfferRetry(
      messenger,
      save: () => controller.change(entry,
          mealType: choice.mealType, servings: choice.servings, edited: choice.edited, date: date),
      failure: "Couldn't save your changes.",
      persist: MediaQuery.accessibleNavigationOf(context),
    );
  }

  /// Says where a just-logged food went, with a way to change it: the meal
  /// is picked before the food, and is easy to get wrong.
  void _offerChange(BuildContext context, WidgetRef ref, FoodEntry entry, String date) {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    // As with "Removed …": replace, not queue, and wait for a screen reader.
    messenger.hideCurrentSnackBar();
    // The day too, when it is not today: the arrows may have been left on
    // another day.
    final today = manilaDayOf(ref.read(nutritionClockProvider)());
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 4),
      persist: MediaQuery.accessibleNavigationOf(context),
      content: Text('Added ${entry.name} to ${mealLabel(entry.mealType).toLowerCase()}${onDay(date, today)}'),
      action: SnackBarAction(
        label: 'Change',
        onPressed: () {
          if (!context.mounted) return;
          // The entry as it is now: with a screen reader this stays up, and
          // the food may have been changed from its row or removed since.
          // On another day there is nothing newer to go by.
          final shown = ref.read(nutritionDayProvider).value;
          final current = shown?.date == date
              ? shown!.entries.where((e) => e.id == entry.id).firstOrNull
              : entry;
          if (current != null) _change(context, ref, current, date);
        },
      ),
    ));
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, FoodEntry entry) async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(nutritionDayProvider.notifier);
    // The entry's own day: the arrows still work while the snackbar shows,
    // and Undo must not log it into whichever day is on screen by then.
    final date = ref.read(nutritionDayProvider).value?.date;
    // Read before the await, while the context is certainly still here.
    final screenReader = MediaQuery.accessibleNavigationOf(context);
    try {
      await controller.remove(entry);
    } catch (_) {
      showErrorSnackBar(messenger, "Couldn't remove — try again.");
      return;
    }
    // Replacing, not queueing behind, an earlier removal's message: with a
    // screen reader that one never times out, so this one would never show.
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 4),
      // An action makes a SnackBar stay up until dismissed by default, which
      // left this one over the meals for as long as the tab was open. A
      // screen reader is the exception: reaching Undo by swiping takes longer
      // than four seconds, so for them it waits.
      persist: screenReader,
      content: Text('Removed ${entry.name}'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () {
          // Each Undo is a new log with its own key, which its Try again
          // sends again, so a put-back that did land is not doubled (NU-4).
          final clientId = newClientId();
          saveOrOfferRetry(
            messenger,
            save: () => controller.log(entry.asFood(), mealType: entry.mealType, servings: entry.servings, date: date, clientId: clientId),
            failure: "Couldn't put ${entry.name} back.",
            persist: screenReader,
          );
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.fs;
    final async = ref.watch(nutritionDayProvider);
    final now = ref.watch(nutritionClockProvider)();
    final today = manilaDayOf(now);
    final day = async.value;

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        bottom: false,
        child: day == null
            ? (async.hasError
                ? FsRetry(
                    fullScreen: true,
                    message: userMessage(async.error!),
                    onRetry: () => ref.invalidate(nutritionDayProvider),
                  )
                : const Center(child: CircularProgressIndicator()))
            : _body(context, ref, day, today, now, busy: async.isLoading, failed: async.hasError),
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, NutritionDay day, String today, DateTime now,
      {required bool busy, required bool failed}) {
    final theme = Theme.of(context);
    final dates = ref.read(nutritionDateProvider.notifier);
    final suggested = mealForTime(now);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        // A heading, as the tabs built on an AppBar have.
        Semantics(header: true, child: Text('Nutrition', style: theme.textTheme.titleLarge)),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton(key: const Key('day.prev'), tooltip: 'Previous day',
                onPressed: busy ? null : () => dates.shift(-1), icon: const Icon(Icons.chevron_left)),
            // Said when an arrow changes it: focus stays on the arrow.
            Expanded(
              child: Semantics(
                container: true,
                liveRegion: true,
                child: Text(dayLabel(day.date, today), textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
              ),
            ),
            IconButton(key: const Key('day.next'), tooltip: 'Next day',
                onPressed: busy || day.date == today ? null : () => dates.shift(1), icon: const Icon(Icons.chevron_right)),
          ],
        ),
        if (busy) const LinearProgressIndicator(minHeight: 2),
        if (failed)
          MaterialBanner(
            content: const Text("Couldn't refresh. Showing the last loaded day."),
            actions: [TextButton(onPressed: () => ref.invalidate(nutritionDayProvider), child: const Text('Try again'))],
          ),
        const SizedBox(height: 8),
        NutritionSummaryCard(day: day, onGoToProfile: onGoToProfile),
        const SizedBox(height: 12),
        SnapMealCard(
          onTap: busy ? null : () => _snap(context, ref, day.date == today ? suggested : null, suggested, day.date),
        ),
        const SizedBox(height: 16),
        // One way to add, by meal. The clock's guess marks the likely
        // meal's row, today only: on another day the time says nothing.
        for (final m in mealTypes)
          MealSection(
            mealType: m,
            entries: day.meals[m]!,
            enabled: !busy,
            suggested: day.date == today && m == suggested,
            onAdd: () => _openLog(context, ref, m),
            onDelete: (e) => _delete(context, ref, e),
            onChange: (e) => _change(context, ref, e, day.date),
          ),
        if (day.hasFatsecret) const FatsecretAttribution(),
      ],
    );
  }
}
