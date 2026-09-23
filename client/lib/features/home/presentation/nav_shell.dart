import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/fs_kit.dart';
import '../../exercises/presentation/exercise_list_screen.dart';
import '../../plans/presentation/start_workout_sheet.dart';
import '../../sessions/presentation/providers.dart' show pendingOutcomeProvider;
import '../../settings/presentation/settings_screen.dart';
import '../../training/presentation/training_shell.dart';
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

  /// How many times the user has arrived at the Train tab from another tab.
  ///
  /// IndexedStack keeps a visited tab alive, so opening Train again rebuilds
  /// nothing -- there is no mount for that tab to notice. This counter is the
  /// notice: it changes each time Train is selected from another tab, and the
  /// Training shell replays its arrival animation whenever it does. A re-tap
  /// of Train while already on it is not an arrival and leaves it alone.
  int _trainOpens = 0;

  @override
  void initState() {
    super.initState();
    // Starts the "+" button's pain-question lookup now, while the user is
    // still on Home, so the tap can answer from a settled result instead of
    // waiting on the network (see showStartWorkoutSheet). Read, not watched:
    // nothing here renders from it. A failure is harmless -- the tap falls
    // back to looking up again itself.
    ProviderScope.containerOf(
      context,
      listen: false,
    ).read(pendingOutcomeProvider);
  }

  void _select(int index) => setState(() {
    // Only an arrival counts: a tap on Train while already there opens
    // nothing, and must not replay the Training shell's intro.
    if (index == _trainIndex && _index != _trainIndex) _trainOpens++;
    _index = index;
    _visited.add(index);
  });

  static const _trainIndex = 1;

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
          _tab(
            _trainIndex,
            () => TrainingShell(
              openCount: _trainOpens,
              onGoToProfile: () => _select(3),
            ),
          ),
          _tab(2, () => const ExerciseListScreen()),
          _tab(3, () => const SettingsScreen()),
        ],
      ),
      bottomNavigationBar: FsNav(
        currentIndex: _index,
        onSelect: _select,
        items: _items,
        onFabTap: () => showStartWorkoutSheet(context),
      ),
    );
  }
}
