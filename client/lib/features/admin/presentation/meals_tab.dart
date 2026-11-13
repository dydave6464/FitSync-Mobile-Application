import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/numbers.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../nutrition/presentation/widgets/dish_photo.dart';
import '../domain/admin_format.dart';
import '../domain/admin_models.dart';
import 'food_form_screen.dart';
import 'providers.dart';
import 'widgets/admin_widgets.dart';
import 'widgets/content_list.dart';

/// The Content tab's Meals segment: FitSync's own foods (never FatSecret
/// copies), Shown, Hidden or Suggested, searchable by name. A row opens the
/// food form.
class MealsTab extends ConsumerWidget {
  const MealsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(adminFoodsQueryProvider);
    final list = ref.watch(adminFoodsProvider);
    // The counts of the last answer, kept while a new list loads.
    final last = list.value?.last;
    String counted(String word, int? count) =>
        count == null ? word : '$word (${groupThousands(count.toDouble())})';

    return AdminContentList<AdminFood>(
      keyPrefix: 'admin.foods',
      searchHint: 'Search foods',
      noun: 'foods',
      query: query,
      chips: [
        (value: 'shown', label: counted('Shown', last?.shownCount)),
        (value: 'hidden', label: counted('Hidden', last?.hiddenCount)),
        (value: 'suggested', label: counted('Suggested', last?.suggestedCount)),
      ],
      list: list,
      emptyMessage: switch (query.chip) {
        'hidden' => 'No hidden foods.',
        'suggested' => 'No suggested foods.',
        _ => 'No foods yet.',
      },
      onSearch: ref.read(adminFoodsQueryProvider.notifier).setSearch,
      onChip: ref.read(adminFoodsQueryProvider.notifier).setChip,
      onLoadMore: ref.read(adminFoodsProvider.notifier).loadMore,
      onRetryMore: ref.read(adminFoodsProvider.notifier).retryMore,
      onRetry: () => ref.invalidate(adminFoodsProvider),
      itemBuilder: (context, food) => _FoodRow(
        key: ValueKey('admin.food.${food.id}'),
        food: food,
        // Pushed over the tabs, so the form has the whole screen and back
        // returns to the list where it was left.
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => FoodFormScreen(food: food)),
        ),
      ),
    );
  }
}

/// "1 cup · 320 kcal", or "320 kcal" with no serving given.
String _subtitle(AdminFood food) {
  final kcal = '${groupThousands(food.kcal.toDouble())} kcal';
  final serving = food.servingDesc;
  return serving == null || serving.isEmpty ? kcal : '$serving · $kcal';
}

class _FoodRow extends StatelessWidget {
  const _FoodRow({super.key, required this.food, this.onTap});

  final AdminFood food;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final subtitle = _subtitle(food);
    final type = foodTypeLabels[food.foodType];
    // The server never suggests a hidden food, and the Suggested chip lists
    // shown ones only, so a hidden food is not tagged Suggested; its meals
    // stay stored for when it is shown again.
    final suggested = food.suggested && !food.hidden;
    final spoken = [
      food.name,
      subtitle,
      ?type,
      if (food.hidden) 'Hidden',
      if (suggested) 'Suggested',
    ].join(', ');

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: FsCard(
        small: true,
        onTap: onTap,
        child: Semantics(
          label: spoken,
          excludeSemantics: true,
          child: Row(
            children: [
              // Decorative: the row's label already names the dish.
              DishPhoto(url: food.photoUrl, width: 40, height: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      food.name,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: t.text,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: t.text2),
                    ),
                    if (type != null)
                      Text(
                        type,
                        style: TextStyle(fontSize: 11, color: t.text3),
                      ),
                    if (suggested)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: StatusTag('Suggested'),
                      ),
                  ],
                ),
              ),
              if (food.hidden) ...[
                const SizedBox(width: 8),
                const StatusTag('Hidden'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
