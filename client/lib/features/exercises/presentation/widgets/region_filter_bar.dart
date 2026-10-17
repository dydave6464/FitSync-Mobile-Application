import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
/// A sideways scroller, as the design draws it. Eight buttons do not fit a
/// small phone at large text, and wrapping them onto three lines would push
/// the list itself half off the screen.
class RegionFilterBar extends ConsumerStatefulWidget {
  const RegionFilterBar({super.key});

  @override
  ConsumerState<RegionFilterBar> createState() => _RegionFilterBarState();
}

class _RegionFilterBarState extends ConsumerState<RegionFilterBar> {
  /// Null is "All".
  static const _options = <MuscleRegion?>[null, ...MuscleRegion.values];

  final _keys = {for (final option in _options) option: GlobalKey()};
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // A choice made on the other screen is restored here, and may be the
    // last button: it must not be lit somewhere off the right-hand edge.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _reveal(animate: false),
    );
  }

  /// Centres the lit button within this bar's own scroller.
  ///
  /// Not `Scrollable.ensureVisible`, which scrolls every scrollable above the
  /// button as well -- and the library is hosted inside other screens' page
  /// views and lists, which a tap on "Legs" has no business moving.
  void _reveal({required bool animate}) {
    if (!mounted || !_scroll.hasClients) return;
    final region = ref.read(selectedFiltersProvider).region;
    final target = _keys[region]?.currentContext?.findRenderObject();
    if (target == null || !target.attached) return;
    final position = _scroll.position;
    final offset = RenderAbstractViewport.of(target)
        .getOffsetToReveal(target, 0.5)
        .offset
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (!animate || MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(offset);
    } else {
      _scroll.animateTo(
        offset,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _choose(MuscleRegion? region) {
    ref.read(selectedFiltersProvider.notifier).setRegion(region);
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(selectedFiltersProvider.select((f) => f.region));

    // Cleared from elsewhere -- the empty list's "Clear filters" -- moves the
    // light back to "All", which may be scrolled out of view.
    ref.listen(
      selectedFiltersProvider.select((f) => f.region),
      (_, _) => WidgetsBinding.instance.addPostFrameCallback(
        (_) => _reveal(animate: true),
      ),
    );

    return SingleChildScrollView(
      key: const Key('library.regions'),
      scrollDirection: Axis.horizontal,
      // Its own controller, never the route's primary one: that belongs to
      // the list.
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          for (final option in _options)
            _target(
              key: _keys[option]!,
              name: option?.name ?? 'all',
              onTap: () => _choose(option),
              chip: FsChip(
                key: Key('library.region.${option?.name ?? 'all'}'),
                label: option?.label ?? 'All',
                selected: option == selected,
                onTap: () => _choose(option),
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
    required GlobalKey key,
    required String name,
    required VoidCallback onTap,
    required Widget chip,
  }) => KeyedSubtree(
    key: key,
    child: GestureDetector(
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
    ),
  );
}
