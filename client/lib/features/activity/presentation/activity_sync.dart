import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/step_permission.dart';
import 'providers.dart';

/// Every resume: move the live count onto a new Manila day if the clock has
/// one, re-check the permission (it may have changed in Settings) and, when
/// counting is on, save the day. DayRollover only acts on a new
/// day, so this is its own listener -- as the Reminders screen
/// (reminders_screen.dart) has its own AppLifecycleListener; ReminderSync
/// does not listen for resumes.
class ActivitySync extends ConsumerStatefulWidget {
  const ActivitySync({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ActivitySync> createState() => _ActivitySyncState();
}

class _ActivitySyncState extends ConsumerState<ActivitySync> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
  }

  Future<void> _onResume() async {
    if (!mounted) return;
    // After a night in the background, the live count starts again from
    // the new midnight.
    ref.read(stepsDayProvider.notifier).refresh();
    ref.invalidate(stepAccessProvider);
    final access = await ref.read(stepAccessProvider.future);
    if (!mounted || access != StepAccess.granted) return;
    await ref.read(activityProvider.notifier).sync();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
