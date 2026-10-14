import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/manila_day.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart' show FsButton;
import '../../exercises/presentation/exercise_list_screen.dart' show describeError;
import '../domain/nutrition.dart';
import 'log_food_screen.dart';
import 'providers.dart';
import 'widgets/fatsecret_attribution.dart';
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

  void _openLog(BuildContext context, String mealType) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => LogFoodScreen(mealType: mealType)),
  );

  Future<void> _delete(BuildContext context, WidgetRef ref, FoodEntry entry) async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(nutritionDayProvider.notifier);
    // The entry's own day: the arrows still work while the snackbar shows,
    // and Undo must not log it into whichever day is on screen by then.
    final date = ref.read(nutritionDayProvider).value?.date;
    try {
      await controller.remove(entry);
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text("Couldn't remove — try again.")));
      return;
    }
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 4),
      content: Text('Removed ${entry.name}'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => controller
            .log(entry.asFood(), mealType: entry.mealType, servings: entry.servings, date: date)
            .catchError((_) => messenger.showSnackBar(const SnackBar(content: Text("Couldn't save — try again.")))),
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
        for (final m in mealTypes)
          MealSection(
            mealType: m,
            entries: day.meals[m]!,
            enabled: !busy,
            onAdd: () => _openLog(context, m),
            onDelete: (e) => _delete(context, ref, e),
          ),
        FsButton(
          key: const Key('nutrition.log'),
          label: 'Log ${mealLabel(suggested).toLowerCase()}',
          icon: const Icon(Icons.add),
          onPressed: busy ? null : () => _openLog(context, suggested),
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
