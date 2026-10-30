import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';
import 'package:fitsync/features/sessions/domain/training_analytics.dart';
import 'package:fitsync/features/sessions/presentation/providers.dart';

/// Stands in for what Pro gates in the app -- the profile (its isPremium:
/// Snap a meal, the share sheet) and the analytics family (its
/// musclesLocked: Volume by muscle) -- and counts how often each is loaded.
class ProLocksProbe {
  ProLocksProbe({this.premium = false});

  /// What the server says on the next load.
  bool premium;
  int profileLoads = 0;
  int analyticsLoads = 0;

  List<Override> get overrides => [
    profileProvider.overrideWith(() => _ProbeProfile(this)),
    trainingAnalyticsProvider.overrideWith((ref, period) async {
      analyticsLoads += 1;
      return TrainingAnalytics(
        period: period,
        volume: const [],
        change: const VolumeChange(totalKg: 0, previousKg: 0, changePct: 0),
        adherence: const Adherence(done: 0, target: 0, weeks: 4),
        muscles: const [],
        musclesLocked: !premium,
      );
    }),
  ];

  /// Keeps both alive the way the Home and Progress tabs do.
  void watch(ProviderContainer container) {
    container.listen(profileProvider, (_, _) {});
    container.listen(trainingAnalyticsProvider('month'), (_, _) {});
  }
}

class _ProbeProfile extends ProfileNotifier {
  _ProbeProfile(this.probe);

  final ProLocksProbe probe;

  @override
  Future<Profile> build() async {
    probe.profileLoads += 1;
    return Profile(
      userId: 7,
      email: 'juan@example.com',
      fullName: 'Juan Dela Cruz',
      onboardingCompleted: true,
      isPremium: probe.premium,
      notificationsEnabled: true,
      equipment: const [],
      injuries: const [],
    );
  }
}
