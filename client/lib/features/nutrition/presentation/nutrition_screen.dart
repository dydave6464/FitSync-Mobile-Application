import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/manila_day.dart';
import '../../../core/theme.dart';
import '../../exercises/presentation/exercise_list_screen.dart' show describeError;
import '../domain/nutrition.dart';
import 'error_snack_bar.dart';
import 'log_food_screen.dart';
import 'providers.dart';
import 'widgets/fatsecret_attribution.dart';
import 'widgets/log_food_sheet.dart';
import 'widgets/meal_section.dart';
import 'widgets/nutrition_summary_card.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _dayLabel(String date, String today) {
  if (date == today) return 'Today';
  final d = DateTime.parse('${date}T00:00:00Z');
  final y = DateTime.parse('${today}T00:00:00Z').subtract(const Duration(days: 1));
  if (d == y) return 'Yesterday';
  return '${_weekdays[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}';
}

class NutritionScreen extends ConsumerWidget {
  const NutritionScreen({super.key, this.onGoToProfile});

  final VoidCallback? onGoToProfile;

  void _openLog(BuildContext context, WidgetRef ref, String mealType) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => LogFoodScreen(
      mealType: mealType,
      onLogged: (entry, date) => _offerChange(context, ref, entry, date),
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
    try {
      await ref.read(nutritionDayProvider.notifier)
          .change(entry, mealType: choice.mealType, servings: choice.servings, edited: choice.edited, date: date);
    } catch (_) {
      showErrorSnackBar(messenger, "Couldn't save — try again.");
    }
  }

  /// Says where a just-logged food went, with a way to change it: the meal
  /// is picked before the food, and is easy to get wrong.
  void _offerChange(BuildContext context, WidgetRef ref, FoodEntry entry, String date) {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    // As with "Removed …": replace, not queue, and wait for a screen reader.
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 4),
      persist: MediaQuery.accessibleNavigationOf(context),
      content: Text('Added ${entry.name} to ${mealLabel(entry.mealType).toLowerCase()}'),
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
        onPressed: () async {
          try {
            await controller.log(entry.asFood(), mealType: entry.mealType, servings: entry.servings, date: date);
          } catch (_) {
            showErrorSnackBar(messenger, "Couldn't save — try again.");
          }
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
                ? _ErrorView(message: describeError(async.error!), onRetry: () => ref.invalidate(nutritionDayProvider))
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
        Text('Nutrition', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton(key: const Key('day.prev'), tooltip: 'Previous day',
                onPressed: busy ? null : () => dates.shift(-1), icon: const Icon(Icons.chevron_left)),
            Expanded(child: Text(_dayLabel(day.date, today), textAlign: TextAlign.center, style: theme.textTheme.titleMedium)),
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

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        TextButton(onPressed: onRetry, child: const Text('Try again')),
      ]),
    ),
  );
}
