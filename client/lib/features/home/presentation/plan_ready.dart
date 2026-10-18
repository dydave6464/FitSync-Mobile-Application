import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether Home should open on "Your plan is ready".
///
/// Raised once, by onboarding, the moment its plan is built, and lowered for
/// good by either of the card's buttons. Held in memory rather than storage:
/// the card belongs to the visit that follows onboarding, and a welcome that
/// came back days later, after an app restart, would no longer be news. That
/// also means nothing can raise it again -- onboarding happens once.
class PlanReadyNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void announce() => state = true;

  void dismiss() => state = false;
}

final planReadyProvider = NotifierProvider<PlanReadyNotifier, bool>(
  PlanReadyNotifier.new,
);
