import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/presentation/providers.dart' show profileProvider;
import '../../sessions/presentation/providers.dart'
    show trainingAnalyticsProvider;
import '../domain/pro_status.dart';
import 'providers.dart';

/// Pro changed: refetches everything in the app that shows or hides a Pro
/// feature, so it unlocks (or locks) at once, with no sign-out.
///
/// - The profile's `isPremium` gates Snap a meal and the share sheet's
///   muscle section.
/// - Volume by muscle is decided by the server on each analytics request
///   (`musclesLocked`), so every cached period of it goes too.
///
/// Neither is autoDispose, and the tabs that show them stay mounted.
void refreshProLocks(WidgetRef ref) {
  ref
    ..invalidate(profileProvider)
    ..invalidate(trainingAnalyticsProvider);
}

/// Keeps the app's Pro locks in line with the server's Pro status.
///
/// The server can change who is Pro without the Pro screen seeing it: a
/// payment it finished on its own (the app was killed while PayMongo's page
/// was open), a `pro:grant`, a period that ended. Whenever a status read
/// disagrees with the profile, [refreshProLocks] runs -- once per read, so a
/// server whose two answers disagree cannot set off a loop.
///
/// Mounted in the shell, it also reads the status once per launch, which is
/// what lets the server finish a payment the app lost.
class ProSync extends ConsumerStatefulWidget {
  const ProSync({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ProSync> createState() => _ProSyncState();
}

class _ProSyncState extends ConsumerState<ProSync> {
  Future<void> _match(bool pro) async {
    final bool premium;
    try {
      // A profile still loading may have been answered before the server
      // finished the payment, so wait for it rather than skip it.
      premium = (await ref.read(profileProvider.future)).isPremium;
    } catch (_) {
      return; // no profile to compare with; its own retry covers it
    }
    if (mounted && premium != pro) refreshProLocks(ref);
  }

  @override
  void initState() {
    super.initState();
    // Listening keeps the status alive -- and read -- for the whole session.
    ref.listenManual<AsyncValue<ProStatus>>(proStatusProvider, (_, next) {
      // Only a finished read: a refresh keeps the old value meanwhile.
      if (next case AsyncData(:final value, isLoading: false)) {
        _match(value.pro);
      }
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
