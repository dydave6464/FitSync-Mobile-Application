import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../nutrition/presentation/error_snack_bar.dart'
    show saveOrOfferRetry;
import '../domain/workout_plan.dart';
import 'providers.dart';

/// Undo for a generated plan (spec 2026-11-14): the snackbar's Undo and the
/// Plan tab's "Bring it back" both land here, so they say the same things.
Future<void> bringBackPreviousPlan({
  required ScaffoldMessengerState messenger,
  required ProviderContainer container,
  required bool persist,
}) => saveOrOfferRetry<WorkoutPlan>(
  messenger,
  save: () => container.read(planRepositoryProvider).restorePrevious(),
  failure: "Couldn't bring back your previous plan.",
  persist: persist,
  onSaved: (_) {
    container.invalidate(activePlanProvider);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(content: Text('Your previous plan is back.')),
    );
  },
);
