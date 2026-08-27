import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

class FilterBar extends ConsumerWidget {
  const FilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(exerciseFiltersProvider);
    final selected = ref.watch(selectedFiltersProvider);
    final notifier = ref.read(selectedFiltersProvider.notifier);

    return filters.when(
      // The filter bar is secondary furniture: if it cannot load, the list
      // below is still perfectly usable unfiltered.
      loading: () => const SizedBox(height: 48),
      error: (_, _) => const SizedBox(height: 48),
      data: (options) => SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          children: [
            if (!selected.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: ActionChip(
                  label: const Text('Clear'),
                  avatar: const Icon(Icons.close, size: 16),
                  onPressed: notifier.clear,
                ),
              ),
            for (final option in options.muscleGroups)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: FilterChip(
                  label: Text(option.value),
                  selected: selected.muscleGroup == option.value,
                  onSelected: (isOn) =>
                      notifier.setMuscleGroup(isOn ? option.value : null),
                ),
              ),
            for (final option in options.equipment)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: FilterChip(
                  label: Text(option.value),
                  selected: selected.equipment == option.value,
                  onSelected: (isOn) =>
                      notifier.setEquipment(isOn ? option.value : null),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
