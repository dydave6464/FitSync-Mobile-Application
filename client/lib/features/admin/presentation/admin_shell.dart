import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/fs_kit.dart';
import 'providers.dart';

/// The admin's app: four tabs over an IndexedStack, as the trainee's
/// `NavShell` has, with no centre button (an admin starts no workouts).
///
/// The tab is kept in [adminTabProvider] rather than in this widget, so a
/// screen inside a tab can switch tabs: see [selectTab].
class AdminShell extends ConsumerStatefulWidget {
  const AdminShell({super.key});

  /// Switches to tab [index]. [usersFilter] asks the Users tab to show one
  /// filter, as Overview's Pro members card does with `'pro'`.
  static void selectTab(
    BuildContext context,
    int index, {
    String? usersFilter,
  }) => ProviderScope.containerOf(
    context,
    listen: false,
  ).read(adminTabProvider.notifier).select(index, usersFilter: usersFilter);

  @override
  ConsumerState<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<AdminShell> {
  static const _items = [
    FsNavItem(
      icon: Icons.insights_outlined,
      activeIcon: Icons.insights,
      label: 'Overview',
    ),
    FsNavItem(
      icon: Icons.people_outline,
      activeIcon: Icons.people,
      label: 'Users',
    ),
    FsNavItem(
      icon: Icons.video_library_outlined,
      activeIcon: Icons.video_library,
      label: 'Content',
    ),
    FsNavItem(
      icon: Icons.payments_outlined,
      activeIcon: Icons.payments,
      label: 'Revenue',
    ),
  ];

  /// Tabs opened at least once. Each is built on its first visit, not at
  /// launch, so Revenue does not load before anyone looks at it; once built,
  /// the IndexedStack keeps it (and its scroll position) alive.
  final _visited = <int>{};

  void _select(int index) => ref.read(adminTabProvider.notifier).select(index);

  Widget _tab(int index, Widget Function() builder) =>
      _visited.contains(index) ? builder() : const SizedBox.shrink();

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(adminTabProvider).index;
    _visited.add(index);

    // Android back on Users, Content or Revenue goes to Overview, as on the
    // trainee's tabs; only back on Overview leaves the app.
    return PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(0);
      },
      child: Scaffold(
        body: IndexedStack(
          index: index,
          children: [
            _tab(0, () => const Center(child: Text('Overview'))),
            _tab(1, () => const Center(child: Text('Users'))),
            _tab(2, () => const Center(child: Text('Content'))),
            _tab(3, () => const Center(child: Text('Revenue'))),
          ],
        ),
        bottomNavigationBar: FsNav(
          currentIndex: index,
          onSelect: _select,
          items: _items,
        ),
      ),
    );
  }
}
