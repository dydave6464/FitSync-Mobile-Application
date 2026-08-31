import 'package:flutter/material.dart';

import '../../../core/widgets/fs_kit.dart';
import '../../exercises/presentation/exercise_list_screen.dart';
import '../../plans/presentation/plan_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import 'home_screen.dart';

/// The signed-in shell: four tabs over an IndexedStack.
///
/// IndexedStack rather than swapping children, so a scrolled list survives a
/// trip to another tab. Each tab screen brings its own Scaffold and AppBar;
/// this only supplies the bar underneath them.
///
/// Pushed detail screens deliberately cover the bar and return to the tab
/// they came from — per-tab Navigators would mean owning back-button and
/// pop-scope behaviour for no benefit at this size.
class NavShell extends StatefulWidget {
  const NavShell({super.key});

  @override
  State<NavShell> createState() => _NavShellState();
}

class _NavShellState extends State<NavShell> {
  int _index = 0;

  /// Every index ever selected, including 0 (the tab mounted at cold start).
  ///
  /// IndexedStack builds every one of its children immediately, offstage or
  /// not — it does not build lazily on its own. Left alone, that means all
  /// four tabs' data providers (two catalogue requests for Browse, on top of
  /// Home's own profile and plan) fire the moment the shell first builds,
  /// for tabs the user may never open. Tracking visited indices here and
  /// swapping an unvisited slot's real screen for a cheap placeholder is
  /// what makes the mount actually lazy, without touching the "keep a
  /// visited tab's state alive" behaviour IndexedStack is here for — once an
  /// index is added, this widget always renders that slot's real screen
  /// again, so its Element (and State) is never torn down.
  final Set<int> _visited = {0};

  void _select(int index) => setState(() {
        _index = index;
        _visited.add(index);
      });

  static const _items = [
    FsNavItem(icon: Icons.home_outlined, label: 'Home'),
    FsNavItem(icon: Icons.fitness_center_outlined, label: 'Train'),
    FsNavItem(icon: Icons.menu_book_outlined, label: 'Browse'),
    FsNavItem(icon: Icons.person_outline, label: 'Profile'),
  ];

  Widget _tab(int index, Widget Function() builder) =>
      _visited.contains(index) ? builder() : const SizedBox.shrink();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          _tab(
            0,
            () => HomeScreen(
              onGoToTrain: () => _select(1),
              onGoToProfile: () => _select(3),
            ),
          ),
          _tab(1, () => const PlanScreen()),
          _tab(2, () => const ExerciseListScreen()),
          _tab(3, () => const SettingsScreen()),
        ],
      ),
      bottomNavigationBar: FsNav(
        currentIndex: _index,
        onSelect: _select,
        items: _items,
      ),
    );
  }
}
