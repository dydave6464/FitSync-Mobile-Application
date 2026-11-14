import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../nutrition/presentation/error_snack_bar.dart'
    show saveOrOfferRetry;
import '../domain/workout_plan.dart';
import 'providers.dart';

/// The refusals that mean the plan this phone holds is out of date: a
/// workout was started on it, or the previous plan is already back (another
/// phone's Undo). The server has no previous plan to offer either way, so
/// the plan is reloaded and the card offering one goes.
const _staleRefusals = {'PLAN_ALREADY_USED', 'NO_PREVIOUS_PLAN'};

/// Whether a bring-back is already on its way to the server. The snackbar's
/// Undo and the Plan tab's card can both be on hand at once; the second ask
/// would only be refused ("no earlier plan") and that refusal would replace
/// the good news on screen.
bool _bringingBack = false;

/// Undo for a generated plan (spec 2026-11-14): the snackbar's Undo and the
/// Plan tab's "Bring it back" both land here, so they say the same things.
/// Answers once the plan has also reloaded (the old one stays on screen
/// while it does), and whether the previous plan came back; an ask made
/// while another is still under way sends nothing and answers false.
Future<bool> bringBackPreviousPlan({
  required ScaffoldMessengerState messenger,
  required ProviderContainer container,
  required bool persist,
}) async {
  if (_bringingBack) return false;
  _bringingBack = true;
  var restored = false;
  var stale = false;
  try {
    await saveOrOfferRetry<WorkoutPlan>(
      messenger,
      save: () async {
        try {
          return await container.read(planRepositoryProvider).restorePrevious();
        } on ApiException catch (e) {
          if (_staleRefusals.contains(e.code)) {
            stale = true;
            container.invalidate(activePlanProvider);
          }
          rethrow;
        }
      },
      failure: "Couldn't bring back your previous plan.",
      persist: persist,
      onSaved: (_) {
        restored = true;
        container.invalidate(activePlanProvider);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          const SnackBar(content: Text('Your previous plan is back.')),
        );
      },
    );
    if (restored || stale) {
      try {
        await container.read(activePlanProvider.future);
      } catch (_) {
        // The Plan tab shows its own error and Try again for a failed load.
      }
    }
  } finally {
    _bringingBack = false;
  }
  return restored;
}
