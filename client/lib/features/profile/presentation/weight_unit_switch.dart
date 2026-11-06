import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/units.dart';
import 'providers.dart' show profileProvider;

/// Saves a kg/lb switch the moment it is tapped, showing the new unit at
/// once rather than when the server answers (up to the API timeout on a slow
/// connection, during which the switch looked dead). Further taps wait for
/// that answer; a refused switch goes back and says so.
///
/// One copy for Settings and onboarding's About step, so the two switches
/// behave the same.
mixin WeightUnitSwitch<W extends ConsumerStatefulWidget> on ConsumerState<W> {
  WeightUnit? _pendingUnit;

  /// The unit to draw: the one on its way to the server, else [saved].
  WeightUnit shownUnit(WeightUnit saved) => _pendingUnit ?? saved;

  Future<void> switchUnit(WeightUnit unit) async {
    if (_pendingUnit != null) return;
    // Captured first: the screen can close while this is on its way (the
    // Body metrics editor), and the app-level messenger outlives it.
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _pendingUnit = unit);
    try {
      await ref.read(profileProvider.notifier).patch({'weightUnit': unit.api});
    } catch (error) {
      // Any failure, not only an ApiException: a timeout or a bad response
      // leaves the unit unsaved just the same. Anything the API layer did not
      // name is logged too: the snack bar says only that it failed, not why.
      if (error is! ApiException) {
        debugPrint('Weight unit switch to ${unit.api} failed: $error');
      }
      messenger.showSnackBar(
        SnackBar(content: Text("Couldn't switch to ${unit.api}. Try again.")),
      );
    } finally {
      // On success the profile already holds the new unit; on failure it
      // still holds the old one, which is what goes back on screen. In a
      // finally so no failure can leave the switch ignoring taps for good.
      if (mounted) setState(() => _pendingUnit = null);
    }
  }
}
