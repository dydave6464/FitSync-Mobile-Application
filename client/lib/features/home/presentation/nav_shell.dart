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

  static const _items = [
    FsNavItem(icon: Icons.home_outlined, label: 'Home'),
    FsNavItem(icon: Icons.fitness_center_outlined, label: 'Train'),
    FsNavItem(icon: Icons.menu_book_outlined, label: 'Browse'),
    FsNavItem(icon: Icons.person_outline, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          HomeScreen(
            onGoToTrain: () => setState(() => _index = 1),
            onGoToProfile: () => setState(() => _index = 3),
          ),
          const PlanScreen(),
          const ExerciseListScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: FsNav(
        currentIndex: _index,
        onSelect: (index) => setState(() => _index = index),
        items: _items,
      ),
    );
  }
}
