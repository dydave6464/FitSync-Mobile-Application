import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/fs_kit.dart';
import '../../domain/muscle_regions.dart';
import '../providers.dart';

/// The library's muscle buttons: "All", then one per body area.
///
/// Single-select, because the areas are how a person thinks of a session
/// ("a legs day"), and a second area is one more button press away rather
/// than a combination the list would have to explain. The catalogue's own
/// nineteen muscle groups stay out of sight: they are what each area sends,
/// not what anyone chooses between.
///
/// Wrapped, not a sideways scroller. As a single scrolling row the last
/// buttons sat past the right-hand edge with nothing to say they were there:
/// on a common phone the row ended with Core flush against the edge, so it
/// read as complete and Cardio was never found. Two lines at normal text cost
/// one row of height; every area stays in sight.
class RegionFilterBar extends ConsumerWidget {
  const RegionFilterBar({super.key});

  /// Null is "All".
  static const _options = <MuscleRegion?>[null, ...MuscleRegion.values];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedFiltersProvider.select((f) => f.region));
    void choose(MuscleRegion? region) =>
        ref.read(selectedFiltersProvider.notifier).setRegion(region);

    return Padding(
      key: const Key('library.regions'),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        children: [
          for (final option in _options)
            _target(
              name: option?.name ?? 'all',
              onTap: () => choose(option),
              chip: FsChip(
                key: Key('library.region.${option?.name ?? 'all'}'),
                label: option?.label ?? 'All',
                selected: option == selected,
                onTap: () => choose(option),
                // Small, as the design draws them; the band around each chip
                // keeps the tap target at full size.
                small: true,
              ),
            ),
        ],
      ),
    );
  }

  /// A chip is painted small; its tap area is not. The chip's own ripple
  /// still answers a tap on the chip, and this catches the band around it.
  /// The band stays out of the semantics tree, so a screen reader stops on
  /// the labelled chip once rather than on a blank wrapper as well.
  Widget _target({
    required String name,
    required VoidCallback onTap,
    required Widget chip,
  }) => GestureDetector(
    key: Key('library.region.$name.target'),
    behavior: HitTestBehavior.opaque,
    excludeFromSemantics: true,
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
        child: Center(widthFactor: 1, child: chip),
      ),
    ),
  );
}
